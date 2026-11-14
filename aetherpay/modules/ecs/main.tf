# =============================================================================
# ECS Module — Main Configuration
# =============================================================================
# Creates the ECS cluster, task definition, Fargate service, Application Load
# Balancer, CloudWatch log group, autoscaling policies and CloudWatch alarms.
# Called once per environment (primary and secondary).
# =============================================================================

# =============================================================================
# ECR Repository
# =============================================================================
# One ECR repository per environment stores the container image.
# Cross-region replication is configured at the registry level in the primary
# environment (see the ecr_replication resource below) so the secondary region
# automatically receives images pushed to the primary.
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-${var.environment}"
  image_tag_mutability = "IMMUTABLE" # Prevents overwriting existing image tags — important for auditability

  # Scan images for known CVEs on every push.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encrypt images at rest using the default AWS-managed ECR key.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr"
  }
}

# ECR lifecycle policy — keeps only the 10 most recent tagged images.
# Untagged images (created during failed builds) are removed after 1 day.
# This prevents the repository from accumulating stale images indefinitely.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

# =============================================================================
# ECR Cross-Region Replication (primary environment only)
# =============================================================================
# Configures the ECR registry in us-east-1 to automatically replicate all
# images to us-west-2. This means every image pushed to the primary ECR
# repository is available in the secondary region without manual copying.
#
# This resource is only meaningful when applied in the primary environment.
# When applied in the secondary environment it creates a no-op replication
# rule pointing back at itself, which AWS ignores. The cleaner approach would
# be a separate global resource, but keeping it here avoids adding a new root
# module just for one resource.
resource "aws_ecr_replication_configuration" "cross_region" {
  replication_configuration {
    rule {
      destination {
        region      = "us-west-2"        # Replicate to the secondary region
        registry_id = var.aws_account_id # Same AWS account
      }

      # Replicate all repositories in this registry (no filter = replicate everything).
      repository_filter {
        filter      = var.project_name # Only replicate aetherpay repositories
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# =============================================================================
# CloudWatch Log Group
# =============================================================================
# ECS tasks send container stdout/stderr logs here via the awslogs log driver.
# Encrypted with the KMS key created in the security module.
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}/${var.environment}"
  retention_in_days = 30 # Retain logs for 30 days then expire automatically
  kms_key_id        = var.cloudwatch_kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-logs"
  }
}

# =============================================================================
# ECS Cluster
# =============================================================================
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  # Enable Container Insights for enhanced cluster-level metrics in CloudWatch.
  # This provides CPU, memory, network and storage metrics per service and task.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# Capacity provider — tells the cluster to use Fargate and Fargate Spot.
# FARGATE_SPOT runs tasks on spare AWS capacity at up to 70% discount.
# We use FARGATE as the primary and FARGATE_SPOT as a secondary option.
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE" # Default to standard Fargate for production reliability
    weight            = 1
    base              = var.ecs_min_count # Always keep at least min_count tasks on standard Fargate
  }
}

# =============================================================================
# ECS Task Definition
# =============================================================================
# Describes the container: which image to run, how much CPU/memory to allocate,
# which IAM roles to use, where to send logs, and which secrets to inject.
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}" # Groups task definition revisions together
  requires_compatibilities = ["FARGATE"]                              # Run on Fargate, not EC2
  network_mode             = "awsvpc"                                 # Required for Fargate — each task gets its own ENI
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory

  # The execution role is used by the Fargate agent to pull the image,
  # write logs and fetch secrets — before the container starts.
  execution_role_arn = var.ecs_task_execution_role_arn

  # The task role is used by the running application code inside the container.
  task_role_arn = var.ecs_task_role_arn

  # Container definition — describes the single application container.
  container_definitions = jsonencode([
    {
      name      = var.project_name
      image     = var.container_image_uri
      essential = true # If this container stops, the entire task stops

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Log configuration — sends container stdout/stderr to CloudWatch Logs.
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Secrets injected as environment variables before the container starts.
      # The execution role has permission to fetch and decrypt these secrets.
      # The application reads them as standard environment variables — it never
      # calls Secrets Manager directly.
      secrets = [
        {
          name      = "DB_CREDENTIALS" # Environment variable name inside the container
          valueFrom = var.db_credentials_secret_arn
        },
        {
          name      = "APP_SECRETS"
          valueFrom = var.app_secrets_secret_arn
        }
      ]

      # Non-sensitive environment variables passed directly.
      environment = [
        {
          name  = "APP_ENV"
          value = var.environment
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-task-definition"
  }
}

# =============================================================================
# Application Load Balancer
# =============================================================================

# Internet-facing ALB in the public subnets.
# Receives traffic from the internet (via WAF) and forwards it to ECS tasks.
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false # Internet-facing
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids # ALB spans all three public subnets

  # Enable deletion protection to prevent accidental ALB deletion.
  enable_deletion_protection = true

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

# Attach the WAF Web ACL to the ALB.
# All requests to the ALB are inspected by WAF before reaching the target group.
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = var.waf_web_acl_arn
}

# Target group — the ALB forwards requests to the ECS tasks registered here.
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-${var.environment}-tg"
  port        = var.container_port
  protocol    = "HTTP" # ALB to ECS task traffic is HTTP (TLS terminates at the ALB)
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate — tasks register by IP, not instance ID

  health_check {
    enabled             = true
    path                = "/health" # Your application must expose this endpoint
    protocol            = "HTTP"
    healthy_threshold   = 2     # Two consecutive successes = healthy
    unhealthy_threshold = 3     # Three consecutive failures = unhealthy
    timeout             = 5     # Seconds to wait for a response
    interval            = 30    # Seconds between health checks
    matcher             = "200" # Only HTTP 200 counts as healthy
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }
}

# HTTP listener — redirects all HTTP traffic to HTTPS.
# This ensures clients that connect on port 80 are upgraded to TLS.
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301" # Permanent redirect
    }
  }
}

# HTTPS listener — terminates TLS and forwards requests to the target group.
# Uses TLS 1.2/1.3 via the ELBSecurityPolicy-TLS13-1-2-2021-06 policy.
# This policy supports TLS 1.3 and falls back to TLS 1.2 for older clients.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # Supports TLS 1.3, minimum TLS 1.2
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# =============================================================================
# ECS Service
# =============================================================================
# The service maintains the desired number of running tasks, registers them
# with the ALB target group, and replaces unhealthy tasks automatically.
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count

  # Use the FARGATE launch type — no EC2 instances to manage.
  launch_type = "FARGATE"

  # Minimum healthy percent: during a deployment, keep at least 100% of desired
  # tasks running before stopping old ones. This prevents downtime.
  deployment_minimum_healthy_percent = 100

  # Maximum percent: allow up to 200% of desired tasks during a deployment
  # so new tasks can start before old ones are stopped.
  deployment_maximum_percent = 200

  # Network configuration — tasks run in private app subnets with no public IPs.
  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.ecs_tasks_security_group_id]
    assign_public_ip = false # Tasks must not receive public IP addresses
  }

  # Register tasks with the ALB target group so the ALB can route traffic to them.
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project_name # Must match the container name in the task definition
    container_port   = var.container_port
  }

  # Wait for the ALB target group and HTTPS listener to exist before creating the service.
  depends_on = [
    aws_lb_listener.https,
    aws_lb_listener.http_redirect,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-service"
  }
}

# =============================================================================
# ECS Autoscaling
# =============================================================================
# Registers the ECS service as a scalable target so we can attach scaling policies.

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.ecs_max_count
  min_capacity       = var.ecs_min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# -----------------------------------------------------------------------------
# Scale-out policy — CPU utilization
# -----------------------------------------------------------------------------
# When average CPU across all tasks exceeds the threshold for 2 consecutive
# evaluation periods (2 minutes), add 2 tasks.
resource "aws_appautoscaling_policy" "cpu_scale_out" {
  name               = "${var.project_name}-${var.environment}-cpu-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity" # Add/remove a specific number of tasks
    cooldown                = 120                # Wait 120 seconds before another scale-out
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0 # Applies when metric is above the alarm threshold
      scaling_adjustment          = 2 # Add 2 tasks
    }
  }
}

# CloudWatch alarm that triggers the CPU scale-out policy.
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  alarm_description   = "ECS CPU utilization is high — scaling out"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2 # Must breach threshold for 2 consecutive periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60 # 60-second evaluation period
  statistic           = "Average"
  threshold           = var.cpu_scale_out_threshold

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_appautoscaling_policy.cpu_scale_out.arn]
}

# -----------------------------------------------------------------------------
# Scale-in policy — CPU utilization
# -----------------------------------------------------------------------------
# When CPU drops below threshold for 5 consecutive periods (5 minutes),
# remove 1 task. Scale-in is more conservative than scale-out to avoid
# removing tasks too aggressively during brief traffic dips.
resource "aws_appautoscaling_policy" "cpu_scale_in" {
  name               = "${var.project_name}-${var.environment}-cpu-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300 # Wait 5 minutes before another scale-in
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0  # Applies when metric is below the alarm threshold
      scaling_adjustment          = -1 # Remove 1 task
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-${var.environment}-cpu-low"
  alarm_description   = "ECS CPU utilization is low — scaling in"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 30 # Scale in when CPU drops below 30%

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_appautoscaling_policy.cpu_scale_in.arn]
}

# -----------------------------------------------------------------------------
# Scale-out policy — Memory utilization
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_policy" "memory_scale_out" {
  name               = "${var.project_name}-${var.environment}-memory-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 2
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.project_name}-${var.environment}-memory-high"
  alarm_description   = "ECS memory utilization is high — scaling out"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.memory_scale_out_threshold

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_appautoscaling_policy.memory_scale_out.arn]
}

# -----------------------------------------------------------------------------
# Scale-out policy — SQS queue depth
# -----------------------------------------------------------------------------
# When the number of visible messages in the SQS queue exceeds the threshold,
# add 2 tasks to process the backlog faster.
resource "aws_appautoscaling_policy" "sqs_scale_out" {
  name               = "${var.project_name}-${var.environment}-sqs-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 2
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_depth_high" {
  alarm_name          = "${var.project_name}-${var.environment}-sqs-depth-high"
  alarm_description   = "SQS queue depth is high — scaling out ECS tasks"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.sqs_scale_out_threshold

  dimensions = {
    QueueName = var.sqs_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.sqs_scale_out.arn]
}

# =============================================================================
# Additional CloudWatch Alarms — operational monitoring
# =============================================================================

# ALB 5xx error rate alarm — alerts when the application is returning server errors.
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx-errors"
  alarm_description   = "ALB is returning 5xx errors — application may be unhealthy"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10 # Alert if more than 10 5xx errors per minute

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  treat_missing_data = "notBreaching" # No data (e.g. no traffic) is not an alarm condition
}

# ECS service task count alarm — alerts if running tasks drop below minimum.
resource "aws_cloudwatch_metric_alarm" "ecs_task_count_low" {
  alarm_name          = "${var.project_name}-${var.environment}-task-count-low"
  alarm_description   = "ECS running task count has dropped below the minimum"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.ecs_min_count

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  treat_missing_data = "breaching" # Missing data here is a problem — treat it as an alarm
}
