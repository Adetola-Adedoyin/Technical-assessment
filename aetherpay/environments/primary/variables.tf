# =============================================================================
# Primary Environment — Input Variables
# =============================================================================
# Variables are defined here and given values in terraform.tfvars.
# Sensitive variables (passwords, keys) must never have default values.
# =============================================================================

variable "aws_region" {
  description = "AWS region for the primary environment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as a prefix in resource names throughout the project."
  type        = string
  default     = "aetherpay"
}

variable "environment" {
  description = "Environment label applied to resource names and tags."
  type        = string
  default     = "primary"
}

# --- Networking ---------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the primary VPC. Must not overlap with the secondary VPC (10.25.0.0/20)."
  type        = string
  default     = "10.24.0.0/20"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the three public subnets, one per Availability Zone."
  type        = list(string)
  default     = ["10.24.0.0/24", "10.24.1.0/24", "10.24.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for the three private application subnets (ECS tasks run here)."
  type        = list(string)
  default     = ["10.24.4.0/24", "10.24.5.0/24", "10.24.6.0/24"]
}

variable "isolated_db_subnet_cidrs" {
  description = "CIDR blocks for the three isolated database/vault subnets (no internet route)."
  type        = list(string)
  default     = ["10.24.8.0/24", "10.24.9.0/24", "10.24.10.0/24"]
}

# --- ECS ----------------------------------------------------------------------

variable "container_image_uri" {
  description = <<-EOT
    Full URI of the container image to run in ECS.
    Format: <account_id>.dkr.ecr.<region>.amazonaws.com/<repo_name>:<tag>
    Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/aetherpay:latest
    Replace this with your actual ECR image URI after pushing your image.
  EOT
  type        = string
  default     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aetherpay:latest"
}

variable "ecs_task_cpu" {
  description = "CPU units allocated to each ECS Fargate task. 1024 = 1 vCPU."
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Memory (MB) allocated to each ECS Fargate task."
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Number of ECS tasks to run under normal conditions in the primary region."
  type        = number
  default     = 3
}

variable "ecs_min_count" {
  description = "Minimum number of ECS tasks. Autoscaling will not scale below this."
  type        = number
  default     = 2
}

variable "ecs_max_count" {
  description = "Maximum number of ECS tasks. Autoscaling will not scale above this."
  type        = number
  default     = 10
}

# --- ALB / TLS ----------------------------------------------------------------

variable "acm_certificate_arn" {
  description = <<-EOT
    ARN of the ACM certificate for the HTTPS listener.
    You must request and validate a certificate in ACM before deploying the ALB listener.
    Steps:
      1. Go to AWS Certificate Manager in us-east-1.
      2. Request a public certificate for your domain.
      3. Complete DNS or email validation.
      4. Paste the resulting ARN here.
    Placeholder value is used until a real certificate is available.
  EOT
  type        = string
  default     = "arn:aws:acm:us-east-1:123456789012:certificate/REPLACE-WITH-REAL-CERT-ARN"
}

# --- Aurora -------------------------------------------------------------------

variable "aurora_master_username" {
  description = "Master username for the Aurora PostgreSQL cluster. Do not use 'admin' or 'root'."
  type        = string
  default     = "aetherpay_admin"
}

variable "aurora_instance_class" {
  description = "Aurora instance class. db.r6g.large is the minimum recommended for production."
  type        = string
  default     = "db.r6g.large"
}

# --- Scaling thresholds -------------------------------------------------------

variable "cpu_scale_out_threshold" {
  description = "CPU utilization percentage that triggers ECS scale-out."
  type        = number
  default     = 70
}

variable "memory_scale_out_threshold" {
  description = "Memory utilization percentage that triggers ECS scale-out."
  type        = number
  default     = 80
}

variable "sqs_scale_out_threshold" {
  description = "Number of visible SQS messages that triggers ECS scale-out."
  type        = number
  default     = 100
}

variable "container_port" {
  description = "Port the application container listens on."
  type        = number
  default     = 8080
}
