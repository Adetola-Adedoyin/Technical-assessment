# =============================================================================
# SQS Module — Outputs
# =============================================================================

output "queue_name" {
  description = "Name of the main SQS queue. Used by the ECS autoscaling CloudWatch alarm."
  value       = aws_sqs_queue.main.name
}

output "queue_arn" {
  description = "ARN of the main SQS queue."
  value       = aws_sqs_queue.main.arn
}

output "queue_url" {
  description = "URL of the main SQS queue. Used by the application to send and receive messages."
  value       = aws_sqs_queue.main.url
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = aws_sqs_queue.dlq.arn
}
