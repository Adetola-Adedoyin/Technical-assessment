# =============================================================================
# Secondary Environment — Input Variables
# =============================================================================
# Same variable structure as the primary environment.
# Defaults reflect the secondary region (us-west-2) and its CIDR range.
# =============================================================================

variable "aws_region" {
  description = "AWS region for the secondary environment."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Short name used as a prefix in resource names throughout the project."
  type        = string
  default     = "aetherpay"
}

variable "environment" {
  description = "Environment label applied to resource names and tags."
  type        = string
  default     = "secondary"
}

# --- Networking ---------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the secondary VPC. Must not overlap with the primary VPC (10.24.0.0/20)."
  type        = string
  default     = "10.25.0.0/20"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the three public subnets, one per Availability Zone."
  type        = list(string)
  default     = ["10.25.0.0/24", "10.25.1.0/24", "10.25.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for the three private application subnets (ECS tasks run here)."
  type        = list(string)
  default     = ["10.25.4.0/24", "10.25.5.0/24", "10.25.6.0/24"]
}

variable "isolated_db_subnet_cidrs" {
  description = "CIDR blocks for the three isolated database/vault subnets (no internet route)."
  type        = list(string)
  default     = ["10.25.8.0/24", "10.25.9.0/24", "10.25.10.0/24"]
}

# --- ECS ----------------------------------------------------------------------

variable "container_image_uri" {
  description = <<-EOT
    Full URI of the container image to run in ECS.
    For the secondary region, this should point to the replicated ECR image in us-west-2.
    ECR cross-region replication copies the image automatically once configured.
    Format: <account_id>.dkr.ecr.us-west-2.amazonaws.com/<repo_name>:<tag>
    Example: 123456789012.dkr.ecr.us-west-2.amazonaws.com/aetherpay:latest
  EOT
  type        = string
  default     = "123456789012.dkr.ecr.us-west-2.amazonaws.com/aetherpay:latest"
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
  description = "Number of ECS tasks to run in warm standby. Lower than primary to save cost."
  type        = number
  default     = 2
}

variable "ecs_min_count" {
  description = "Minimum number of ECS tasks. Autoscaling will not scale below this."
  type        = number
  default     = 2
}

variable "ecs_max_count" {
  description = "Maximum number of ECS tasks. Must be high enough to handle full production load during failover."
  type        = number
  default     = 10
}

# --- ALB / TLS ----------------------------------------------------------------

variable "acm_certificate_arn" {
  description = <<-EOT
    ARN of the ACM certificate for the HTTPS listener in us-west-2.
    Certificates are regional — you need a separate certificate in us-west-2.
    Steps:
      1. Go to AWS Certificate Manager in us-west-2.
      2. Request a public certificate for your domain.
      3. Complete DNS or email validation.
      4. Paste the resulting ARN here.
  EOT
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/REPLACE-WITH-REAL-CERT-ARN"
}

# --- Aurora -------------------------------------------------------------------

variable "aurora_instance_class" {
  description = "Aurora instance class for the secondary (read-only) cluster."
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

variable "global_cluster_id" {
  description = "ID of the Aurora Global Cluster created in the primary environment. Required for the secondary Aurora cluster to join the global cluster. Obtain this from the primary environment's aurora output after applying the primary environment."
  type        = string
  default     = ""
}
