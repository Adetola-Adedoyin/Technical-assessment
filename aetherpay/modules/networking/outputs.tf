# =============================================================================
# Networking Module — Outputs
# =============================================================================
# These values are consumed by the ECS, Aurora, and security modules.
# Only outputs that are genuinely needed by other modules are included.
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC. Used by security groups and VPC endpoints in other modules."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC. Used in security group rules that reference the VPC range."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the three public subnets. Used by the ALB and NAT Gateways."
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of the three private application subnets. Used by ECS services."
  value       = aws_subnet.private_app[*].id
}

output "isolated_db_subnet_ids" {
  description = "IDs of the three isolated database subnets. Used by the Aurora subnet group."
  value       = aws_subnet.isolated_db[*].id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group. Referenced by the ECS task security group ingress rule."
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "ID of the ECS task security group. Used by the ECS service and Aurora ingress rule."
  value       = aws_security_group.ecs_tasks.id
}

output "aurora_security_group_id" {
  description = "ID of the Aurora security group. Used by the Aurora cluster."
  value       = aws_security_group.aurora.id
}

output "availability_zones" {
  description = "The three Availability Zone names used by this network. Used by Aurora for multi-AZ placement."
  value       = local.azs
}
