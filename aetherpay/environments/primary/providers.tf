# =============================================================================
# Primary Environment — AWS Provider Configuration
# =============================================================================
# Configures the AWS provider for us-east-1.
#
# The default_tags block applies a common set of tags to every resource
# created by this provider. This makes cost allocation and resource
# identification straightforward without repeating tags on every resource.
# =============================================================================

provider "aws" {
  region = var.aws_region # us-east-1, set in variables.tf

  default_tags {
    tags = {
      Project     = "aetherpay"
      Environment = "primary"
      Region      = var.aws_region
      ManagedBy   = "terraform"
    }
  }
}
