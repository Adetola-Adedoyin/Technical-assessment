# =============================================================================
# Secondary Environment — Terraform Version Requirements and Remote Backend
# =============================================================================
# Same provider version pins as the primary environment.
# State is stored in the same S3 bucket but under a different key so the two
# environments have completely separate state files.
#
# PREREQUISITE: Run bootstrap/ before running terraform init here.
#               Replace YOUR_ACCOUNT_ID with your actual AWS account ID.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "aetherpay-terraform-state-YOUR_ACCOUNT_ID"
    key            = "secondary/terraform.tfstate" # Separate key from the primary environment
    region         = "us-east-1"                   # The state bucket always lives in us-east-1
    dynamodb_table = "aetherpay-terraform-locks"
    encrypt        = true
  }
}
