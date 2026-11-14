# =============================================================================
# ECS Module — Outputs
# =============================================================================

output "alb_dns_name" {
  description = "DNS name of the ALB. Used by Route 53 failover routing in the global module."
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB. Required for Route 53 alias records."
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the ALB. Used to create Route 53 health checks."
  value       = aws_lb.main.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.app.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository. Use this when pushing container images."
  value       = aws_ecr_repository.app.repository_url
}
