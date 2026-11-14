# =============================================================================
# SQS Module — Input Variables
# =============================================================================

variable "project_name" {
  description = "Short name used as a prefix in all resource names."
  type        = string
}

variable "environment" {
  description = "Environment label (primary or secondary)."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt SQS messages at rest."
  type        = string
}

variable "message_retention_seconds" {
  description = "How long SQS retains a message if it is not consumed. Default is 4 days."
  type        = number
  default     = 345600 # 4 days in seconds
}

variable "visibility_timeout_seconds" {
  description = "How long a message is hidden from other consumers after being received. Set this to at least as long as your task processing time."
  type        = number
  default     = 300 # 5 minutes
}

variable "max_receive_count" {
  description = "Number of times a message can be received before being moved to the dead-letter queue."
  type        = number
  default     = 3
}
