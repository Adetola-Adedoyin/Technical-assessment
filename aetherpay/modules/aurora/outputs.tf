# =============================================================================
# Aurora Module — Outputs
# =============================================================================

output "global_cluster_id" {
  description = "ID of the Aurora Global Cluster. Pass this to the secondary environment's aurora module as global_cluster_id."
  value       = var.is_primary ? aws_rds_global_cluster.main[0].id : var.global_cluster_id
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint of the primary Aurora cluster. Use this for read/write connections."
  value       = var.is_primary ? aws_rds_cluster.primary[0].endpoint : null
}

output "primary_cluster_reader_endpoint" {
  description = "Reader endpoint of the primary Aurora cluster. Use this for read-only connections."
  value       = var.is_primary ? aws_rds_cluster.primary[0].reader_endpoint : null
}

output "secondary_cluster_reader_endpoint" {
  description = "Reader endpoint of the secondary Aurora cluster. Read-only until promoted."
  value       = var.is_primary ? null : aws_rds_cluster.secondary[0].reader_endpoint
}
