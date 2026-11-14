# =============================================================================
# Global — AWS Provider Configuration
# =============================================================================
# Route 53 is a global AWS service. The provider region here is used only
# for the health check resources, which are always created in us-east-1
# regardless of which region you specify.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Separate state file for the global configuration.
  # Apply bootstrap/ before running terraform init here.
  # Replace YOUR_ACCOUNT_ID with your actual AWS account ID.
  backend "s3" {
    bucket         = "aetherpay-terraform-state-YOUR_ACCOUNT_ID"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aetherpay-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1" # Route 53 health checks are always managed from us-east-1

  default_tags {
    tags = {
      Project   = "aetherpay"
      Component = "global"
      ManagedBy = "terraform"
    }
  }
}
