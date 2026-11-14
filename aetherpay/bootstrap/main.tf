# =============================================================================
# AetherPay Bootstrap
# =============================================================================
# PURPOSE: Create the S3 bucket and DynamoDB table that store Terraform remote
#          state for all AetherPay environments.
#
# HOW TO USE:
#   1. Run this configuration ONCE before deploying any other environment.
#   2. Use your own AWS credentials with permissions to create S3 and DynamoDB.
#   3. Commands:
#        terraform init
#        terraform apply
#
# IMPORTANT: This configuration itself uses LOCAL state (no backend block).
#            Do not delete the local terraform.tfstate file it produces.
#            That file records that these backend resources exist.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Bootstrap runs in us-east-1 because the state bucket lives in the primary region.
provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# S3 Bucket — stores Terraform state files for all environments
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  # Bucket names must be globally unique. The account ID suffix achieves this.
  bucket = "aetherpay-terraform-state-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion of the bucket that holds all state files.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "aetherpay-terraform-state"
    Project = "aetherpay"
    Purpose = "terraform-remote-state"
  }
}

# Enable versioning so every state file write is preserved.
# This allows you to recover from accidental state corruption.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt all state files at rest using AES-256 (SSE-S3).
# This protects secrets that Terraform writes into state.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access to the state bucket.
# State files can contain sensitive values — they must never be public.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# DynamoDB Table — provides state locking
# -----------------------------------------------------------------------------
# When two Terraform operations run at the same time, the lock prevents them
# from writing conflicting state. Terraform requires the partition key to be
# named "LockID".
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "aetherpay-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # No capacity planning needed for a locks table
  hash_key     = "LockID"          # Required name — Terraform looks for this key

  attribute {
    name = "LockID"
    type = "S" # String type
  }

  tags = {
    Name    = "aetherpay-terraform-locks"
    Project = "aetherpay"
    Purpose = "terraform-state-locking"
  }
}

# -----------------------------------------------------------------------------
# Data source — retrieves the current AWS account ID for the bucket name
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Outputs — values you need when configuring backends in other environments
# -----------------------------------------------------------------------------
output "state_bucket_name" {
  description = "Name of the S3 bucket that stores Terraform state. Use this in each environment's backend configuration."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_lock_table_name" {
  description = "Name of the DynamoDB table used for state locking. Use this in each environment's backend configuration."
  value       = aws_dynamodb_table.terraform_locks.name
}
