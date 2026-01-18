# -----------------------------------------------------------------------------
# Terraform Provider Configuration for Multi-Account AWS Governance Platform
# -----------------------------------------------------------------------------
# governance/providers.tf
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# =============================================================================
# Default Provider (Governance Account)
# =============================================================================
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Governance Account Provider (Explicit Alias)
# =============================================================================
provider "aws" {
  alias  = "governance"
  region = var.primary_region

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Dev Account Provider
# =============================================================================
provider "aws" {
  alias  = "dev"
  region = var.primary_region

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Staging Account Provider
# =============================================================================
provider "aws" {
  alias  = "staging"
  region = var.primary_region

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Prod Account Provider
# =============================================================================
provider "aws" {
  alias  = "prod"
  region = var.primary_region

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Management Account Provider (Fallback to Assume Role if no profile)
# =============================================================================
provider "aws" {
  alias  = "management"
  region = var.primary_region
  # Keeping assume_role here as no profile was provided for Management
  assume_role {
    role_arn     = "arn:aws:iam::${var.management_account_id}:role/${var.terraform_role_name}"
    session_name = "TerraformManagement"
  }

  default_tags {
    tags = var.default_tags
  }
}
