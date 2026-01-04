# -----------------------------------------------------------------------------
# Terraform Provider Configuration for Multi-Account AWS Governance Platform
# -----------------------------------------------------------------------------
# staging/providers.tf
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
# Default Provider (Staging Account)
# =============================================================================
provider "aws" {
  region  = var.primary_region
  profile = "Staging"

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Governance Account Provider (Explicit Alias)
# =============================================================================
provider "aws" {
  alias   = "governance"
  region  = var.primary_region
  profile = "governance"

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Dev Account Provider
# =============================================================================
provider "aws" {
  alias   = "dev"
  region  = var.primary_region
  profile = "Dev"

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Staging Account Provider
# =============================================================================
provider "aws" {
  alias   = "staging"
  region  = var.primary_region
  profile = "Staging"

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Prod Account Provider
# =============================================================================
provider "aws" {
  alias   = "prod"
  region  = var.primary_region
  profile = "Prod"

  default_tags {
    tags = var.default_tags
  }
}

# =============================================================================
# Management Account Provider
# =============================================================================
provider "aws" {
  alias  = "management"
  region = var.primary_region
  assume_role {
    role_arn     = "arn:aws:iam::${var.management_account_id}:role/${var.terraform_role_name}"
    session_name = "TerraformManagement"
  }

  default_tags {
    tags = var.default_tags
  }
}
