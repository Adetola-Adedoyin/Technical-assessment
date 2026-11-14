# =============================================================================
# Security Module — Main Configuration
# =============================================================================
# Creates IAM roles, KMS keys, Secrets Manager secrets and the WAF Web ACL.
# This module is called once per environment (primary and secondary).
# =============================================================================

# =============================================================================
# KMS Keys
# =============================================================================
# We use customer-managed KMS keys (CMKs) rather than AWS-managed keys so that
# we control the key policy, can audit key usage, and can revoke access if needed.

# -----------------------------------------------------------------------------
# KMS Key — Secrets Manager
# -----------------------------------------------------------------------------
# Encrypts all secrets stored in Secrets Manager.
# The key policy allows the ECS task execution role to use it for decryption
# (added after the role is created, via the key policy document below).
resource "aws_kms_key" "secrets" {
  description             = "Encrypts AetherPay secrets in Secrets Manager for the ${var.environment} environment"
  deletion_window_in_days = 30   # Key is retained for 30 days after deletion request before permanent removal
  enable_key_rotation     = true # AWS rotates the key material annually — best practice

  tags = {
    Name = "${var.project_name}-${var.environment}-secrets-key"
  }
}

# Human-readable alias so the key is easy to identify in the AWS console.
resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-${var.environment}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# -----------------------------------------------------------------------------
# KMS Key — CloudWatch Logs
# -----------------------------------------------------------------------------
# Encrypts ECS application log data at rest in CloudWatch Logs.
resource "aws_kms_key" "cloudwatch" {
  description             = "Encrypts AetherPay CloudWatch log groups for the ${var.environment} environment"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # CloudWatch Logs requires an explicit key policy granting the logs service
  # permission to use this key. Without this, log group encryption will fail.
  policy = data.aws_iam_policy_document.cloudwatch_kms_policy.json

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudwatch-key"
  }
}

resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/${var.project_name}-${var.environment}-cloudwatch"
  target_key_id = aws_kms_key.cloudwatch.key_id
}

# Key policy that grants CloudWatch Logs permission to use this KMS key.
# Without this, CloudWatch cannot encrypt or decrypt log data.
data "aws_iam_policy_document" "cloudwatch_kms_policy" {
  # Statement 1: Allow the account root full key administration.
  # This prevents the key from becoming unmanageable if IAM roles are deleted.
  statement {
    sid    = "EnableRootAccountKeyAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Statement 2: Allow the CloudWatch Logs service to use this key.
  # The service principal must match the region where logs are written.
  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]
  }
}

# -----------------------------------------------------------------------------
# KMS Key — Aurora
# -----------------------------------------------------------------------------
# Encrypts Aurora PostgreSQL storage at rest.
resource "aws_kms_key" "aurora" {
  description             = "Encrypts AetherPay Aurora PostgreSQL storage for the ${var.environment} environment"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-key"
  }
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${var.project_name}-${var.environment}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

# =============================================================================
# IAM — ECS Task Execution Role
# =============================================================================
# Used by the Fargate agent (not your application) to:
#   - Pull the container image from ECR
#   - Write container logs to CloudWatch Logs
#   - Fetch secrets from Secrets Manager before the container starts
#
# Your application code does NOT use this role.

resource "aws_iam_role" "ecs_task_execution" {
  name        = "${var.project_name}-${var.environment}-ecs-execution-role"
  description = "Allows the ECS Fargate agent to pull images, write logs and fetch secrets"

  # Trust policy: only the ECS tasks service can assume this role.
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-execution-role"
  }
}

# Trust policy shared by both ECS roles — only ECS tasks can assume them.
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

# Attach the AWS-managed ECS task execution policy.
# This grants the standard ECR pull and CloudWatch Logs write permissions.
resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional inline policy: allow the execution role to fetch secrets from
# Secrets Manager and decrypt them using the KMS key.
# This is needed so secrets can be injected into the container as environment
# variables before the application starts — without the app needing to call
# Secrets Manager itself.
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.project_name}-${var.environment}-ecs-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = data.aws_iam_policy_document.ecs_execution_secrets.json
}

data "aws_iam_policy_document" "ecs_execution_secrets" {
  # Allow reading secrets — scoped to secrets with the project name prefix only.
  statement {
    sid    = "GetApplicationSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue", # Retrieve the secret value
    ]

    # Restrict to secrets that belong to this project and environment.
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project_name}/${var.environment}/*",
    ]
  }

  # Allow decryption using the secrets KMS key.
  statement {
    sid    = "DecryptSecretsKMSKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [aws_kms_key.secrets.arn]
  }
}

# =============================================================================
# IAM — ECS Task Role
# =============================================================================
# Used by your running application code inside the container.
# Grants only the permissions the application needs at runtime.
# Does NOT include ECR or Secrets Manager access — those are handled before
# the container starts by the execution role above.

resource "aws_iam_role" "ecs_task" {
  name        = "${var.project_name}-${var.environment}-ecs-task-role"
  description = "Grants running ECS application containers their runtime AWS permissions"

  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task-role"
  }
}

# Inline policy: runtime permissions for the application.
# Scoped to the specific SQS queues and CloudWatch namespace for this project.
resource "aws_iam_role_policy" "ecs_task_runtime" {
  name = "${var.project_name}-${var.environment}-ecs-task-runtime"
  role = aws_iam_role.ecs_task.id

  policy = data.aws_iam_policy_document.ecs_task_runtime.json
}

data "aws_iam_policy_document" "ecs_task_runtime" {
  # Allow the application to send and receive SQS messages.
  # Scoped to queues with the project name prefix in this account and region.
  statement {
    sid    = "SQSAccess"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ChangeMessageVisibility",
    ]

    resources = [
      "arn:aws:sqs:${var.aws_region}:${var.aws_account_id}:${var.project_name}-${var.environment}-*",
    ]
  }

  # Allow the application to publish custom CloudWatch metrics.
  # No resource restriction needed — PutMetricData does not support resource-level permissions.
  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricData",
    ]

    resources = ["*"]

    # Restrict to the application's own CloudWatch namespace to limit blast radius.
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["AetherPay/${var.environment}"]
    }
  }
}

# =============================================================================
# Secrets Manager — Application Secret Placeholders
# =============================================================================
# These secrets are created as empty placeholders.
# Populate them manually in the AWS console or via the AWS CLI after deployment.
# The application retrieves these at startup via the task execution role.
# NEVER put real secret values in Terraform code or state.

# Database credentials secret — holds the Aurora connection string and password.
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}/${var.environment}/db-credentials"
  description = "Aurora PostgreSQL connection credentials for the AetherPay application"
  kms_key_id  = aws_kms_key.secrets.arn # Encrypt with our CMK, not the AWS-managed default key

  # Retain the secret for 7 days after deletion so accidental deletes can be recovered.
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-credentials"
  }
}

# Placeholder value — replace this with real credentials via the AWS console or CLI.
# Example CLI command to set the real value:
#   aws secretsmanager put-secret-value \
#     --secret-id aetherpay/primary/db-credentials \
#     --secret-string '{"username":"aetherpay_admin","password":"REPLACE_ME","host":"<aurora-endpoint>","port":5432,"dbname":"aetherpay"}'
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = "aetherpay_admin"
    password = "REPLACE_WITH_REAL_PASSWORD"
    host     = "REPLACE_WITH_AURORA_ENDPOINT"
    port     = 5432
    dbname   = "aetherpay"
  })

  # Ignore future changes to this value in Terraform so that manual secret
  # rotation does not cause Terraform to overwrite the real password.
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Application API keys secret — holds third-party API credentials.
resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "${var.project_name}/${var.environment}/app-secrets"
  description = "Application API keys and configuration secrets for AetherPay"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-app-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  secret_string = jsonencode({
    api_key    = "REPLACE_WITH_REAL_API_KEY"
    api_secret = "REPLACE_WITH_REAL_API_SECRET"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# =============================================================================
# WAF Web ACL
# =============================================================================
# The WAF Web ACL is attached to the ALB in the ECS module.
# It inspects all inbound HTTP/HTTPS requests before they reach the ALB.
#
# Rules are evaluated in priority order (lower number = evaluated first).
# If a request matches a BLOCK rule, it is dropped immediately.
# If no rule matches, the default action (allow) applies.

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-${var.environment}-waf"
  description = "WAF Web ACL for AetherPay ${var.environment} ALB"
  scope       = "REGIONAL" # REGIONAL attaches to ALBs; CLOUDFRONT attaches to CloudFront distributions

  # Default action: allow requests that do not match any rule.
  default_action {
    allow {}
  }

  # -------------------------------------------------------------------------
  # Rule 1 — Rate limiting (priority 1, evaluated first)
  # -------------------------------------------------------------------------
  # Blocks any single IP address that sends more than 1,000 requests within
  # any 5-minute window. This limits brute-force and credential-stuffing attacks.
  rule {
    name     = "RateLimitPerIP"
    priority = 1

    action {
      block {} # Drop requests that exceed the rate limit
    }

    statement {
      rate_based_statement {
        limit                 = 1000 # Maximum requests per IP in the evaluation window
        aggregate_key_type    = "IP" # Count requests per source IP address
        evaluation_window_sec = 300  # 5-minute (300 second) sliding window
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-rate-limit"
      sampled_requests_enabled   = true # Store sample requests for debugging
    }
  }

  # -------------------------------------------------------------------------
  # Rule 2 — AWS Managed Rules: Core Rule Set (priority 2)
  # -------------------------------------------------------------------------
  # The Core Rule Set (CRS) protects against common web exploits including
  # SQL injection, cross-site scripting (XSS), and other OWASP Top 10 threats.
  # AWS maintains and updates these rules automatically.
  rule {
    name     = "AWSManagedRulesCoreRuleSet"
    priority = 2

    # override_action instead of action — required for managed rule groups.
    # none means we use the actions defined inside the managed rule group itself.
    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-core-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # Rule 3 — AWS Managed Rules: Known Bad Inputs (priority 3)
  # -------------------------------------------------------------------------
  # Blocks requests containing patterns associated with known exploits,
  # such as Log4j (Log4Shell) payloads and other injection patterns.
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # Rule 4 — AWS Managed Rules: Amazon IP Reputation List (priority 4)
  # -------------------------------------------------------------------------
  # Blocks requests from IP addresses that AWS has identified as associated
  # with bots, scrapers, and other malicious sources.
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Top-level visibility config — enables WAF metrics and request sampling
  # for the entire Web ACL (not just individual rules).
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-waf"
  }
}
