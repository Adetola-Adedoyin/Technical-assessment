# =============================================================================
# SQS Module — Main Configuration
# =============================================================================
# Creates the application SQS queue and a dead-letter queue (DLQ).
#
# The main queue receives messages from the application.
# If a message fails processing more than max_receive_count times, it is
# moved to the DLQ automatically. The DLQ holds failed messages so they
# can be inspected and reprocessed without being lost.
# =============================================================================

# -----------------------------------------------------------------------------
# Dead-Letter Queue
# -----------------------------------------------------------------------------
# Created first because the main queue references its ARN in the redrive policy.
resource "aws_sqs_queue" "dlq" {
  name = "${var.project_name}-${var.environment}-dlq"

  # Retain failed messages in the DLQ for 14 days so there is time to investigate.
  message_retention_seconds = 1209600 # 14 days

  # Encrypt messages at rest using the KMS key from the security module.
  kms_master_key_id = var.secrets_kms_key_arn

  tags = {
    Name = "${var.project_name}-${var.environment}-dlq"
  }
}

# -----------------------------------------------------------------------------
# Main Application Queue
# -----------------------------------------------------------------------------
resource "aws_sqs_queue" "main" {
  name = "${var.project_name}-${var.environment}-queue"

  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # Encrypt messages at rest.
  kms_master_key_id = var.secrets_kms_key_arn

  # Redrive policy: after max_receive_count failed delivery attempts,
  # move the message to the DLQ instead of discarding it.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-queue"
  }
}
