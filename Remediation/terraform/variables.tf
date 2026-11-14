# =============================================================================
# variables.tf — Shared input variables for Part 2 Terraform snippets
# =============================================================================
# Both snippet-a-remediated.tf and snippet-b-remediated.tf live in the same
# Terraform root module. Shared variables are declared here once to avoid
# duplicate declarations. Environment-specific values must be supplied via
# terraform.tfvars or -var flags — no real IDs, ARNs, or secrets are hardcoded.
# =============================================================================

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC — used to scope HTTPS egress to VPC endpoints"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the Application Load Balancer"
  type        = string
}

variable "aurora_security_group_id" {
  description = "Security group ID of the Aurora PostgreSQL cluster"
  type        = string
}

variable "redis_security_group_id" {
  description = "Security group ID of the ElastiCache Redis cluster"
  type        = string
}

variable "container_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 8080
}

variable "app_s3_bucket_arn" {
  description = "ARN of the S3 bucket the application needs to access"
  type        = string
}

variable "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret holding database credentials"
  type        = string
}

variable "app_secrets_secret_arn" {
  description = "ARN of the Secrets Manager secret holding application API keys"
  type        = string
}

variable "aws_region" {
  description = "AWS region for this environment"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for this environment"
  type        = string
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "aetherpay"
}

variable "environment" {
  description = "Environment name (e.g. staging, primary, secondary)"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "IDs of the private application subnets where ECS tasks run"
  type        = list(string)
}

variable "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS task ENIs"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role (used by the Fargate agent)"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN of the ECS task role (used by the application container)"
  type        = string
}

variable "container_image_uri" {
  description = "Full ECR image URI including tag"
  type        = string
}

variable "ecs_desired_count" {
  description = "Initial desired task count — Auto Scaling manages this after first deploy"
  type        = number
  default     = 2
}

variable "ecs_min_count" {
  description = "Minimum number of ECS tasks (Auto Scaling lower bound)"
  type        = number
  default     = 2
}

variable "ecs_max_count" {
  description = "Maximum number of ECS tasks (Auto Scaling upper bound)"
  type        = number
  default     = 10
}

variable "ecs_task_cpu" {
  description = "CPU units for the ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Memory in MiB for the ECS task"
  type        = number
  default     = 1024
}

variable "redis_node_type" {
  description = "ElastiCache node type (e.g. cache.t3.micro)"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_subnet_group_name" {
  description = "Name of the ElastiCache subnet group (must be in private/isolated subnets)"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the HTTPS ALB listener"
  type        = string
}

variable "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL to attach to the ALB"
  type        = string
}

variable "cloudwatch_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt CloudWatch log groups"
  type        = string
}
