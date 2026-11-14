# =============================================================================
# Primary Environment — Terraform Version Requirements and Remote Backend
# =============================================================================
# This file pins the Terraform CLI version and AWS provider version so that
# all team members and CI pipelines use identical tooling.
#
# The backend block tells Terraform to store its state file in S3 instead of
# locally. The DynamoDB table prevents two concurrent applies from corrupting
# the state.
#
# PREREQUISITE: Run bootstrap/ before running terraform init here.
#               Replace YOUR_ACCOUNT_ID with your actual AWS account ID.
# =============================================================================

terraform {
  # Minimum Terraform CLI version required to use this configuration.
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Allows patch updates within the 5.x major version
    }
  }

  # Remote backend — state is stored in S3, locks are stored in DynamoDB.
  # This backend block cannot use variables, so the bucket name is written
  # directly here. Replace YOUR_ACCOUNT_ID with your actual AWS account ID.
  backend "s3" {
    bucket         = "aetherpay-terraform-state-YOUR_ACCOUNT_ID"
    key            = "primary/terraform.tfstate" # Path inside the bucket for this environment's state
    region         = "us-east-1"                 # The bucket lives in the primary region
    dynamodb_table = "aetherpay-terraform-locks" # DynamoDB table for state locking
    encrypt        = true                        # Encrypt the state file at rest
  }
}
