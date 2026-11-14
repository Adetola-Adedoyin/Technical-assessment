# =============================================================================
# Networking Module — Input Variables
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
  description = "AWS region this network is being deployed into."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Primary: 10.24.0.0/20. Secondary: 10.25.0.0/20."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of three CIDR blocks for public subnets, one per Availability Zone."
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "List of three CIDR blocks for private application subnets (ECS tasks run here)."
  type        = list(string)
}

variable "isolated_db_subnet_cidrs" {
  description = "List of three CIDR blocks for isolated database subnets (no internet route)."
  type        = list(string)
}
