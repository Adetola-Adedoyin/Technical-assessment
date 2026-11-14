# =============================================================================
# Global — Input Variables
# =============================================================================
# These values come from the outputs of the primary and secondary environments.
# After applying both environments, run:
#   cd environments/primary && terraform output
#   cd environments/secondary && terraform output
# Then fill in terraform.tfvars with the real values.
# =============================================================================

variable "project_name" {
  description = "Short name used as a prefix in resource names."
  type        = string
  default     = "aetherpay"
}

variable "domain_name" {
  description = <<-EOT
    The domain name for the Route 53 hosted zone.
    A public hosted zone will be created for this name.
    NOTE: 'adetola' is not a registered public domain. To receive real internet
    traffic you must either:
      a) Register 'adetola.com' (or similar) through Route 53 or another registrar
         and update the NS records to point to this hosted zone, or
      b) Use an existing registered domain you own.
    The hosted zone will be created regardless — DNS resolution only works
    publicly once the domain is registered and NS records are delegated.
  EOT
  type        = string
  default     = "adetola.com"
}

variable "app_subdomain" {
  description = "Subdomain for the application. The full DNS name will be <app_subdomain>.<domain_name>."
  type        = string
  default     = "app"
}

variable "health_check_path" {
  description = "HTTP path that Route 53 health checks will request on the ALB. Must return HTTP 200."
  type        = string
  default     = "/health"
}

variable "dns_ttl" {
  description = "TTL in seconds for the failover DNS records. Lower values mean faster failover but more DNS queries. 60 seconds is a reasonable balance."
  type        = number
  default     = 60
}

# --- Primary environment ALB values (from environments/primary outputs) -------

variable "primary_alb_dns_name" {
  description = "DNS name of the primary ALB. Get this from: cd environments/primary && terraform output alb_dns_name"
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Hosted zone ID of the primary ALB. Get this from: cd environments/primary && terraform output alb_zone_id"
  type        = string
}

# --- Secondary environment ALB values (from environments/secondary outputs) ---

variable "secondary_alb_dns_name" {
  description = "DNS name of the secondary ALB. Get this from: cd environments/secondary && terraform output alb_dns_name"
  type        = string
}

variable "secondary_alb_zone_id" {
  description = "Hosted zone ID of the secondary ALB. Get this from: cd environments/secondary && terraform output alb_zone_id"
  type        = string
}
