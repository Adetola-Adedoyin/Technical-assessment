# =============================================================================
# Primary Environment — Outputs
# =============================================================================

# --- Networking ---------------------------------------------------------------

output "vpc_id" {
  description = "Primary VPC ID."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Primary public subnet IDs."
  value       = module.networking.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Primary private application subnet IDs."
  value       = module.networking.private_app_subnet_ids
}

output "isolated_db_subnet_ids" {
  description = "Primary isolated database subnet IDs."
  value       = module.networking.isolated_db_subnet_ids
}

# --- ECS / ALB ----------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of the primary ALB. Used in Route 53 failover routing."
  value       = module.ecs.alb_dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the primary ALB. Required for Route 53 alias records."
  value       = module.ecs.alb_zone_id
}

output "ecr_repository_url" {
  description = "ECR repository URL. Push your container image here."
  value       = module.ecs.ecr_repository_url
}

# --- Aurora -------------------------------------------------------------------

output "aurora_global_cluster_id" {
  description = "ID of the Aurora Global Cluster. Set this as global_cluster_id in the secondary environment's terraform.tfvars before applying the secondary environment."
  value       = module.aurora.global_cluster_id
}

output "aurora_primary_endpoint" {
  description = "Writer endpoint of the primary Aurora cluster."
  value       = module.aurora.primary_cluster_endpoint
}

output "aurora_primary_reader_endpoint" {
  description = "Reader endpoint of the primary Aurora cluster."
  value       = module.aurora.primary_cluster_reader_endpoint
}

# --- SQS ----------------------------------------------------------------------

output "sqs_queue_url" {
  description = "URL of the primary SQS queue."
  value       = module.sqs.queue_url
}
