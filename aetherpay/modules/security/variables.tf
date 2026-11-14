# =============================================================================
# Security Module — Input Variables
# =============================================================================

variable "project_name" {
  description = "Short name used as a prefix in all resource names."
  type        = string
}

variable "environment" {
  description = "Environment label (primary or secondary) used in resource names and tags."
  type        = string
}

variable "aws_region" {
  description = "AWS region this security configuration is deployed into."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID. Used to construct IAM policy resource ARNs."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID from the networking module. Used to scope the WAF to the correct ALB."
  type        = string
}
