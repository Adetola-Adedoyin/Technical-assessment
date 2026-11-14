# =============================================================================
# Secondary Environment — Outputs
# =============================================================================

# --- Networking ---------------------------------------------------------------

output "vpc_id" {
  description = "Secondary VPC ID."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Secondary public subnet IDs."
  value       = module.networking.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Secondary private application subnet IDs."
  value       = module.networking.private_app_subnet_ids
}

output "isolated_db_subnet_ids" {
  description = "Secondary isolated database subnet IDs."
  value       = module.networking.isolated_db_subnet_ids
}

# --- ECS / ALB ----------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of the secondary ALB. Used in Route 53 failover routing."
  value       = module.ecs.alb_dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the secondary ALB. Required for Route 53 alias records."
  value       = module.ecs.alb_zone_id
}

output "ecr_repository_url" {
  description = "ECR repository URL in us-west-2. Images are replicated here automatically."
  value       = module.ecs.ecr_repository_url
}

# --- Aurora -------------------------------------------------------------------

output "aurora_secondary_reader_endpoint" {
  description = "Reader endpoint of the secondary Aurora cluster. Read-only until manually promoted."
  value       = module.aurora.secondary_cluster_reader_endpoint
}

# --- SQS ----------------------------------------------------------------------

output "sqs_queue_url" {
  description = "URL of the secondary SQS queue."
  value       = module.sqs.queue_url
}
