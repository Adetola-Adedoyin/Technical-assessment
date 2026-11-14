# =============================================================================
# Global — Outputs
# =============================================================================

output "hosted_zone_id" {
  description = "ID of the Route 53 hosted zone."
  value       = aws_route53_zone.main.zone_id
}

output "hosted_zone_name_servers" {
  description = <<-EOT
    The four name server records AWS assigned to this hosted zone.
    Update your domain registrar's NS records to these values to make
    the domain publicly resolvable.
  EOT
  value       = aws_route53_zone.main.name_servers
}

output "app_dns_name" {
  description = "The full DNS name clients use to reach the application (e.g. app.adetola.com)."
  value       = aws_route53_record.primary.fqdn
}

output "primary_health_check_id" {
  description = "ID of the Route 53 health check monitoring the primary ALB."
  value       = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  description = "ID of the Route 53 health check monitoring the secondary ALB."
  value       = aws_route53_health_check.secondary.id
}
