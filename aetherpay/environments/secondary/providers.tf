# =============================================================================
# Secondary Environment — AWS Provider Configuration
# =============================================================================
# Configures the AWS provider for us-west-2.
# The secondary environment is independently deployable — it does not reference
# the primary environment's provider or state.
# =============================================================================

provider "aws" {
  region = var.aws_region # us-west-2, set in variables.tf

  default_tags {
    tags = {
      Project     = "aetherpay"
      Environment = "secondary"
      Region      = var.aws_region
      ManagedBy   = "terraform"
    }
  }
}
