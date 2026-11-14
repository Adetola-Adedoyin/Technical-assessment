# =============================================================================
# Global — Route 53 Failover Routing
# =============================================================================
# Creates the hosted zone, health checks and failover DNS records that direct
# traffic between the primary (us-east-1) and secondary (us-west-2) regions.
#
# APPLY ORDER:
#   1. environments/primary  — must be fully applied first
#   2. environments/secondary — must be fully applied second
#   3. global/               — apply this last, after both environments are up
#
# After applying both environments, retrieve their ALB outputs and set them
# in this module's terraform.tfvars before running terraform apply here.
# =============================================================================

# =============================================================================
# Route 53 Hosted Zone
# =============================================================================
# A public hosted zone makes the domain resolvable from the public internet.
# AWS assigns four name server (NS) records to the hosted zone automatically.
#
# IMPORTANT: Creating a hosted zone does not make the domain work publicly.
# You must register the domain (e.g. adetola.com) with a registrar and
# update the domain's NS records to point to the four NS values AWS assigns.
# Until that is done, only Route 53's own resolver will return these records.
resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "AetherPay public hosted zone — managed by Terraform"

  tags = {
    Name = "${var.project_name}-hosted-zone"
  }
}

# =============================================================================
# Route 53 Health Checks
# =============================================================================
# Health checks poll the ALB endpoints periodically. When a health check fails,
# Route 53 stops returning the associated DNS record and falls back to the
# secondary record.
#
# Health checks for ALBs must use the ALB's public DNS name (not an IP address)
# because ALBs have multiple IP addresses that change over time.

# -----------------------------------------------------------------------------
# Primary region health check — monitors the us-east-1 ALB
# -----------------------------------------------------------------------------
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns_name # The ALB DNS name to poll
  port              = 443
  type              = "HTTPS"               # Poll over HTTPS
  resource_path     = var.health_check_path # Path that must return HTTP 200
  failure_threshold = 3                     # 3 consecutive failures = unhealthy
  request_interval  = 30                    # Poll every 30 seconds

  # Enable latency graphs in the Route 53 console for this health check.
  measure_latency = true

  tags = {
    Name = "${var.project_name}-primary-health-check"
  }
}

# -----------------------------------------------------------------------------
# Secondary region health check — monitors the us-west-2 ALB
# -----------------------------------------------------------------------------
resource "aws_route53_health_check" "secondary" {
  fqdn              = var.secondary_alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  measure_latency = true

  tags = {
    Name = "${var.project_name}-secondary-health-check"
  }
}

# =============================================================================
# Route 53 Failover DNS Records
# =============================================================================
# Two records share the same DNS name (app.adetola.com).
# Route 53 uses the failover routing policy to decide which record to return:
#   - PRIMARY record is returned when its health check is passing
#   - SECONDARY record is returned when the primary health check is failing
#
# Both records are ALIAS records pointing to their respective ALBs.
# Alias records are free (no per-query charge) and automatically follow
# the ALB's IP addresses as they change.

# -----------------------------------------------------------------------------
# Primary failover record — points to the us-east-1 ALB
# -----------------------------------------------------------------------------
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}" # e.g. app.adetola.com
  type    = "A"

  # Failover routing policy — this record is the PRIMARY.
  failover_routing_policy {
    type = "PRIMARY"
  }

  # set_identifier must be unique among records with the same name and type.
  set_identifier = "primary"

  # Associate this record with the primary health check.
  # If this health check fails, Route 53 stops returning this record.
  health_check_id = aws_route53_health_check.primary.id

  # Alias record — points directly to the ALB without a separate IP lookup.
  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true # Also check the ALB's own health before returning this record
  }
}

# -----------------------------------------------------------------------------
# Secondary failover record — points to the us-west-2 ALB
# -----------------------------------------------------------------------------
resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary"

  # The secondary record does not need a health check attached.
  # Route 53 will return it whenever the primary is unhealthy.
  # Optionally attach the secondary health check if you want Route 53 to
  # avoid returning the secondary record when it is also unhealthy.
  health_check_id = aws_route53_health_check.secondary.id

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }
}
