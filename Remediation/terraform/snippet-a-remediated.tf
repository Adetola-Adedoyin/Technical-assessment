# =============================================================================
# Snippet A — Remediated
# =============================================================================
# Corrects four vulnerabilities from the original Snippet A:
#   1. Public HTTP ingress from 0.0.0.0/0  → restricted to ALB SG only
#   2. Unrestricted internal protocol access → specific ports and sources only
#   3. Unrestricted outbound traffic         → scoped to required destinations
#   4. Overly permissive IAM policy          → specific actions and resource ARNs
# =============================================================================

# Variables are declared in variables.tf (shared across both snippet files).

# -----------------------------------------------------------------------------
# Security Group — ECS Application Tasks
# -----------------------------------------------------------------------------
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  description = "Controls traffic to and from ECS application task ENIs"
  vpc_id      = var.vpc_id

  # --- Ingress ---

  # Allow the application port from the ALB security group only.
  # Direct internet access to tasks is not permitted — all traffic must
  # arrive via the ALB. This replaces the original 0.0.0.0/0 HTTP rule
  # and the broad VPC CIDR all-protocol rule.
  ingress {
    description     = "Application port from ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  # --- Egress ---

  # Allow HTTPS outbound to the VPC CIDR only.
  # AWS service traffic (ECR, Secrets Manager, CloudWatch, SQS) is handled
  # by VPC endpoints and stays within the VPC — no internet egress needed.
  egress {
    description = "HTTPS to AWS service VPC endpoints within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow PostgreSQL egress to the Aurora security group only.
  egress {
    description     = "PostgreSQL to Aurora cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.aurora_security_group_id]
  }

  # Allow Redis egress to the ElastiCache security group only.
  egress {
    description     = "Redis to ElastiCache cluster"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.redis_security_group_id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  }
}

# -----------------------------------------------------------------------------
# IAM — ECS Task Role
# -----------------------------------------------------------------------------
# The task role is assumed by the running application container.
# It grants only the permissions the application needs at runtime.

resource "aws_iam_role" "ecs_task" {
  name        = "${var.project_name}-${var.environment}-ecs-task-role"
  description = "Runtime permissions for the AetherPay application container"

  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task-role"
  }
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ecs_task_runtime" {
  name   = "${var.project_name}-${var.environment}-ecs-task-runtime"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_runtime.json
}

data "aws_iam_policy_document" "ecs_task_runtime" {

  # S3 access — scoped to the specific application bucket and required actions only.
  # The original snippet used s3:* on * which grants full S3 access to the entire account.
  statement {
    sid    = "S3AppBucketAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]

    # Restrict to the specific bucket and its objects — not all S3 resources.
    resources = [
      var.app_s3_bucket_arn,
      "${var.app_s3_bucket_arn}/*",
    ]
  }

  # Secrets Manager access — scoped to the specific secret ARNs for this environment.
  # The original snippet used the non-existent action "secretsmanager:ReadSecret".
  # The correct action is "secretsmanager:GetSecretValue".
  statement {
    sid    = "GetApplicationSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      var.db_credentials_secret_arn,
      var.app_secrets_secret_arn,
    ]
  }

  # CloudWatch Metrics — PutMetricData does not support resource-level restrictions.
  # The namespace condition limits the blast radius to this application's metrics only.
  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricData",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["AetherPay/${var.environment}"]
    }
  }
}
