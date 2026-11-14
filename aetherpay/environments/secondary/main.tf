# =============================================================================
# Secondary Environment — Root Module
# =============================================================================
# Identical module structure to the primary environment.
# Key differences:
#   - aurora module: is_primary = false, joins the existing global cluster
#   - ecs module: lower desired_count (warm standby)
#   - All networking uses the 10.25.0.0/20 CIDR range
#
# DEPLOYMENT ORDER:
#   Apply the primary environment fully before applying this environment.
#   After the primary apply, retrieve the global_cluster_id output and set it
#   in this environment's terraform.tfvars as global_cluster_id.
# =============================================================================

# Data source — retrieves the current AWS account ID at plan time.
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  project_name             = var.project_name
  environment              = var.environment
  aws_region               = var.aws_region
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  isolated_db_subnet_cidrs = var.isolated_db_subnet_cidrs
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------
module "security" {
  source = "../../modules/security"

  project_name   = var.project_name
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
  vpc_id         = module.networking.vpc_id
}

# -----------------------------------------------------------------------------
# SQS
# -----------------------------------------------------------------------------
module "sqs" {
  source = "../../modules/sqs"

  project_name        = var.project_name
  environment         = var.environment
  secrets_kms_key_arn = module.security.secrets_kms_key_arn
}

# -----------------------------------------------------------------------------
# Aurora — Secondary cluster (joins the global cluster from the primary environment)
# -----------------------------------------------------------------------------
# IMPORTANT: Set global_cluster_id in terraform.tfvars to the value of the
# aurora.global_cluster_id output from the primary environment before applying.
# Example:
#   global_cluster_id = "aetherpay-global-cluster"
module "aurora" {
  source = "../../modules/aurora"

  project_name             = var.project_name
  environment              = var.environment
  aws_region               = var.aws_region
  isolated_db_subnet_ids   = module.networking.isolated_db_subnet_ids
  aurora_security_group_id = module.networking.aurora_security_group_id
  aurora_kms_key_arn       = module.security.aurora_kms_key_arn
  aurora_instance_class    = var.aurora_instance_class
  availability_zones       = module.networking.availability_zones
  is_primary               = false # Secondary — joins the existing global cluster
  global_cluster_id        = var.global_cluster_id
}

# -----------------------------------------------------------------------------
# ECS — Cluster, service, ALB, autoscaling (warm standby)
# -----------------------------------------------------------------------------
module "ecs" {
  source = "../../modules/ecs"

  project_name   = var.project_name
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Networking inputs
  vpc_id                      = module.networking.vpc_id
  private_app_subnet_ids      = module.networking.private_app_subnet_ids
  public_subnet_ids           = module.networking.public_subnet_ids
  ecs_tasks_security_group_id = module.networking.ecs_tasks_security_group_id
  alb_security_group_id       = module.networking.alb_security_group_id

  # Security inputs
  ecs_task_execution_role_arn = module.security.ecs_task_execution_role_arn
  ecs_task_role_arn           = module.security.ecs_task_role_arn
  cloudwatch_kms_key_arn      = module.security.cloudwatch_kms_key_arn
  waf_web_acl_arn             = module.security.waf_web_acl_arn
  db_credentials_secret_arn   = module.security.db_credentials_secret_arn
  app_secrets_secret_arn      = module.security.app_secrets_secret_arn
  acm_certificate_arn         = var.acm_certificate_arn

  # Container configuration
  container_image_uri = var.container_image_uri
  container_port      = var.container_port
  ecs_task_cpu        = var.ecs_task_cpu
  ecs_task_memory     = var.ecs_task_memory
  ecs_desired_count   = var.ecs_desired_count # 2 tasks for warm standby
  ecs_min_count       = var.ecs_min_count
  ecs_max_count       = var.ecs_max_count

  # Autoscaling thresholds
  cpu_scale_out_threshold    = var.cpu_scale_out_threshold
  memory_scale_out_threshold = var.memory_scale_out_threshold
  sqs_scale_out_threshold    = var.sqs_scale_out_threshold
  sqs_queue_name             = module.sqs.queue_name
}
