# =============================================================================
# Aurora Module — Main Configuration
# =============================================================================
# Creates an Aurora PostgreSQL Global Database.
#
# The primary environment (is_primary = true) creates:
#   - The Aurora Global Cluster resource (the container that spans regions)
#   - The primary DB cluster (read/write, in us-east-1 isolated subnets)
#   - Two DB instances in the primary cluster
#
# The secondary environment (is_primary = false) creates:
#   - A secondary DB cluster that joins the existing global cluster
#   - One DB instance in the secondary cluster (read-only)
#
# REPLICATION CAVEAT:
#   Aurora Global Database replication is asynchronous. Typical replication lag
#   is under one second in normal conditions, but this does not guarantee RPO=0.
#   If the primary region fails before a transaction is replicated, that
#   transaction will be lost. Promoting the secondary to read/write is a manual
#   operation performed in the AWS console or via the AWS CLI — it does not
#   happen automatically.
# =============================================================================

# =============================================================================
# Aurora Global Cluster
# =============================================================================
# The global cluster is the top-level container that links the primary and
# secondary regional clusters together. It is created only in the primary
# environment. The secondary environment references it by ID.
resource "aws_rds_global_cluster" "main" {
  count = var.is_primary ? 1 : 0 # Only create this resource in the primary environment

  global_cluster_identifier = "${var.project_name}-global-cluster"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4" # Aurora PostgreSQL 15.4
  database_name             = "aetherpay"
  storage_encrypted         = true # Encryption is required for Global Database
  deletion_protection       = true # Prevent accidental deletion of the global cluster
}

# =============================================================================
# DB Subnet Group
# =============================================================================
# Tells Aurora which subnets it can place instances in.
# We use the isolated DB subnets — no internet route, no public IPs.
resource "aws_db_subnet_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-subnet-group"
  description = "Isolated subnets for Aurora PostgreSQL in the ${var.environment} environment"
  subnet_ids  = var.isolated_db_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-subnet-group"
  }
}

# =============================================================================
# DB Cluster Parameter Group
# =============================================================================
# Applies PostgreSQL-level configuration to the cluster.
# Using a custom parameter group (even with defaults) means we can tune
# settings later without recreating the cluster.
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-params"
  family      = "aurora-postgresql15"
  description = "Aurora PostgreSQL 15 parameter group for AetherPay ${var.environment}"

  # Enforce SSL connections to the database.
  # rds.force_ssl = 1 rejects any connection that does not use TLS.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-params"
  }
}

# =============================================================================
# Aurora DB Cluster — Primary
# =============================================================================
# The primary cluster handles all read/write traffic.
# It is created only in the primary environment.
resource "aws_rds_cluster" "primary" {
  count = var.is_primary ? 1 : 0

  cluster_identifier        = "${var.project_name}-${var.environment}-cluster"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  global_cluster_identifier = aws_rds_global_cluster.main[0].id # Links this cluster to the global cluster

  database_name   = "aetherpay"
  master_username = var.aurora_master_username

  # The master password is managed by RDS and stored in Secrets Manager automatically.
  # manage_master_user_password = true tells RDS to create and rotate the password.
  # This avoids storing the password in Terraform state entirely.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.aurora_kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = [var.aurora_security_group_id]
  availability_zones              = var.availability_zones

  storage_encrypted = true
  kms_key_id        = var.aurora_kms_key_arn

  # Retain automated backups for 7 days.
  backup_retention_period = 7

  # Preferred backup window — choose a low-traffic period.
  preferred_backup_window = "03:00-04:00"

  # Preferred maintenance window.
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  deletion_protection = true # Prevent accidental cluster deletion

  # Skip final snapshot during development. Set to false in production
  # and provide a final_snapshot_identifier.
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-cluster"
  }
}

# Two Aurora instances in the primary cluster — one per AZ for high availability.
# Aurora automatically promotes one instance to writer and keeps the other as reader.
resource "aws_rds_cluster_instance" "primary" {
  count = var.is_primary ? 2 : 0

  identifier         = "${var.project_name}-${var.environment}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary[0].id
  instance_class     = var.aurora_instance_class
  engine             = "aurora-postgresql"
  engine_version     = "15.4"

  db_subnet_group_name = aws_db_subnet_group.aurora.name

  # Enable Performance Insights for query-level monitoring.
  performance_insights_enabled = true

  # Enable automatic minor version upgrades during the maintenance window.
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-instance-${count.index + 1}"
  }
}

# =============================================================================
# Aurora DB Cluster — Secondary
# =============================================================================
# The secondary cluster is read-only and receives replicated data from the
# primary cluster via the Aurora Global Database mechanism.
# It is created only in the secondary environment.
#
# IMPORTANT: The secondary cluster must be created AFTER the primary cluster
# has been fully provisioned. The global_cluster_id variable must be set to
# the ID of the global cluster created in the primary environment.
resource "aws_rds_cluster" "secondary" {
  count = var.is_primary ? 0 : 1

  cluster_identifier        = "${var.project_name}-${var.environment}-cluster"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  global_cluster_identifier = var.global_cluster_id # ID of the global cluster from the primary environment

  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = [var.aurora_security_group_id]
  availability_zones              = var.availability_zones

  storage_encrypted = true
  kms_key_id        = var.aurora_kms_key_arn

  # Secondary clusters do not have a master username or password —
  # authentication is managed by the global cluster.

  deletion_protection = true
  skip_final_snapshot = true

  # The secondary cluster depends on the global cluster existing first.
  # Since we reference global_cluster_id as a variable (not a resource reference),
  # we add an explicit lifecycle note here as documentation.
  # Ensure the primary environment is fully applied before applying the secondary.

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-cluster"
  }
}

# One Aurora instance in the secondary cluster.
# This instance is read-only — it cannot accept write traffic until the
# cluster is manually promoted to a standalone cluster during failover.
resource "aws_rds_cluster_instance" "secondary" {
  count = var.is_primary ? 0 : 1

  identifier         = "${var.project_name}-${var.environment}-instance-1"
  cluster_identifier = aws_rds_cluster.secondary[0].id
  instance_class     = var.aurora_instance_class
  engine             = "aurora-postgresql"
  engine_version     = "15.4"

  db_subnet_group_name = aws_db_subnet_group.aurora.name

  performance_insights_enabled = true
  auto_minor_version_upgrade   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-instance-1"
  }
}
