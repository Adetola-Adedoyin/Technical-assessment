# =============================================================================
# Security Module — Outputs
# =============================================================================
# Values consumed by the ECS module (roles, WAF ARN, log encryption key)
# and the Aurora module (Aurora KMS key).
# =============================================================================

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role. Passed to the ECS task definition."
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role. Passed to the ECS task definition for runtime permissions."
  value       = aws_iam_role.ecs_task.arn
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL. Attached to the ALB in the ECS module."
  value       = aws_wafv2_web_acl.main.arn
}

output "cloudwatch_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt CloudWatch log groups."
  value       = aws_kms_key.cloudwatch.arn
}

output "aurora_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Aurora PostgreSQL storage."
  value       = aws_kms_key.aurora.arn
}

output "secrets_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Secrets Manager secrets."
  value       = aws_kms_key.secrets.arn
}

output "db_credentials_secret_arn" {
  description = "ARN of the database credentials secret in Secrets Manager. Referenced in the ECS task definition."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "app_secrets_secret_arn" {
  description = "ARN of the application secrets in Secrets Manager. Referenced in the ECS task definition."
  value       = aws_secretsmanager_secret.app_secrets.arn
}
