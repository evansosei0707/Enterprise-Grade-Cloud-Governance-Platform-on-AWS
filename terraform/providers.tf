# -----------------------------------------------------------------------------
# Terraform Provider Configuration for Multi-Account AWS Governance Platform
# -----------------------------------------------------------------------------
# This configuration sets up provider aliases for all AWS accounts in the org.
# Use provider = aws.<alias> in modules to target specific accounts.
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
# Default Provider (Governance Account - Control Plane)
# =============================================================================
provider "aws" {
  region = var.primary_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.governance_account_id}:role/${var.terraform_role_name}"
    session_name = "TerraformGovernance"
  }

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

# =============================================================================
# Governance Account Provider (Explicit Alias)
# =============================================================================
provider "aws" {
  alias  = "governance"
  region = var.primary_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.governance_account_id}:role/${var.terraform_role_name}"
    session_name = "TerraformGovernance"
  }

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

  assume_role {
    role_arn     = "arn:aws:iam::${var.dev_account_id}:role/${var.terraform_role_name}"
    session_name = "TerraformDev"
  }

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

  assume_role {
    role_arn     = "arn:aws:iam::${var.staging_account_id}:role/${var.terraform_role_name}"
    session_name = "TerraformStaging"
  }

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

  assume_role {
    role_arn     = "arn:aws:iam::${var.prod_account_id}:role/${var.terraform_role_name}"
    session_name = "TerraformProd"
  }

  default_tags {
    tags = var.default_tags
  }
}
