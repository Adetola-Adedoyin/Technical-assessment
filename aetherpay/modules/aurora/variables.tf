# =============================================================================
# Aurora Module — Input Variables
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
  description = "AWS region this Aurora cluster is deployed into."
  type        = string
}

variable "isolated_db_subnet_ids" {
  description = "IDs of the isolated database subnets where Aurora instances run."
  type        = list(string)
}

variable "aurora_security_group_id" {
  description = "Security group ID for Aurora (from networking module)."
  type        = string
}

variable "aurora_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Aurora storage (from security module)."
  type        = string
}

variable "aurora_instance_class" {
  description = "Aurora instance class. db.r6g.large is the minimum recommended for production."
  type        = string
}

variable "aurora_master_username" {
  description = "Master username for the Aurora cluster. Only used in the primary environment."
  type        = string
  default     = ""
}

variable "is_primary" {
  description = "Set to true for the primary environment (creates the global cluster and primary DB cluster). Set to false for the secondary environment (joins the existing global cluster as a read-only secondary)."
  type        = bool
}

variable "global_cluster_id" {
  description = "ID of the Aurora Global Cluster to join. Only required when is_primary = false."
  type        = string
  default     = ""
}

variable "availability_zones" {
  description = "List of three Availability Zone names for Aurora multi-AZ placement."
  type        = list(string)
}
