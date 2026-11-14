# =============================================================================
# ECS Module — Input Variables
# =============================================================================

variable "project_name" {
  description = "Short name used as a prefix in all resource names."
  type        = string
}

variable "environment" {
  description = "Environment label (primary or secondary)."
  type        = string
}

variable "aws_region" {
  description = "AWS region this ECS cluster is deployed into."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID. Used to construct ECR repository URIs."
  type        = string
}

# --- Networking inputs (from networking module outputs) -----------------------

variable "vpc_id" {
  description = "VPC ID where the ECS service and ALB are deployed."
  type        = string
}

variable "private_app_subnet_ids" {
  description = "IDs of the private application subnets where ECS tasks run."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets where the ALB is placed."
  type        = list(string)
}

variable "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks (from networking module)."
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID for the ALB (from networking module)."
  type        = string
}

# --- Security inputs (from security module outputs) --------------------------

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role (from security module)."
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN of the ECS task role (from security module)."
  type        = string
}

variable "cloudwatch_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt CloudWatch log groups."
  type        = string
}

variable "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL to attach to the ALB."
  type        = string
}

variable "db_credentials_secret_arn" {
  description = "ARN of the database credentials secret in Secrets Manager."
  type        = string
}

variable "app_secrets_secret_arn" {
  description = "ARN of the application secrets in Secrets Manager."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the HTTPS listener."
  type        = string
}

# --- Container configuration -------------------------------------------------

variable "container_image_uri" {
  description = "Full URI of the container image to run. Replace with your actual ECR image URI."
  type        = string
}

variable "container_port" {
  description = "Port the application container listens on."
  type        = number
  default     = 8080
}

variable "ecs_task_cpu" {
  description = "CPU units for each Fargate task. 1024 = 1 vCPU."
  type        = number
}

variable "ecs_task_memory" {
  description = "Memory (MB) for each Fargate task."
  type        = number
}

variable "ecs_desired_count" {
  description = "Number of ECS tasks to run under normal conditions."
  type        = number
}

variable "ecs_min_count" {
  description = "Minimum number of ECS tasks for autoscaling."
  type        = number
}

variable "ecs_max_count" {
  description = "Maximum number of ECS tasks for autoscaling."
  type        = number
}

# --- Autoscaling thresholds --------------------------------------------------

variable "cpu_scale_out_threshold" {
  description = "CPU utilization % that triggers scale-out."
  type        = number
}

variable "memory_scale_out_threshold" {
  description = "Memory utilization % that triggers scale-out."
  type        = number
}

variable "sqs_scale_out_threshold" {
  description = "Number of visible SQS messages that triggers scale-out."
  type        = number
}

variable "sqs_queue_name" {
  description = "Name of the SQS queue used for the queue-depth autoscaling metric."
  type        = string
}
