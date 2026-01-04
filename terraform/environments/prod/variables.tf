# -----------------------------------------------------------------------------
# Global Variables for Cloud Governance Platform
# -----------------------------------------------------------------------------
# These variables are used across all modules and environments.
# Account IDs are configured for the organization structure.
# -----------------------------------------------------------------------------

# =============================================================================
# Organization & Account Configuration
# =============================================================================

variable "organization_id" {
  description = "AWS Organization ID"
  type        = string
}

variable "management_account_id" {
  description = "Management (Org Root) Account ID"
  type        = string
}

variable "governance_account_id" {
  description = "Governance Account ID - hosts control plane"
  type        = string
}

variable "dev_account_id" {
  description = "Development Account ID"
  type        = string
}

variable "staging_account_id" {
  description = "Staging Account ID"
  type        = string
}

variable "prod_account_id" {
  description = "Production Account ID"
  type        = string
}

# =============================================================================
# Regional Configuration
# =============================================================================

variable "primary_region" {
  description = "Primary AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "enabled_regions" {
  description = "List of AWS regions to enable for Config aggregation"
  type        = list(string)
  default = [
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
    "eu-west-1",
    "eu-central-1",
    "ap-southeast-1",
    "ap-northeast-1"
  ]
}

# =============================================================================
# IAM Role Configuration
# =============================================================================

variable "terraform_role_name" {
  description = "Name of the IAM role Terraform assumes in each account"
  type        = string
  default     = "TerraformExecutionRole"
}

variable "remediation_role_name" {
  description = "Name of the cross-account remediation role in member accounts"
  type        = string
  default     = "CloudGovernanceRemediationRole"
}

# =============================================================================
# Project Naming
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "cloud-governance"
}

variable "environment" {
  description = "Environment name (governance, dev, staging, prod)"
  type        = string
  default     = "governance"
}

# =============================================================================
# Tagging
# =============================================================================

variable "default_tags" {
  description = "Default tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "CloudGovernancePlatform"
    ManagedBy   = "Terraform"
    Owner       = "Platform-Engineering"
    CostCenter  = "INFRA-001"
    Environment = "governance"
  }
}

# =============================================================================
# Required Tags for Compliance
# =============================================================================

variable "required_tags" {
  description = "Tags that must be present on all resources"
  type        = list(string)
  default = [
    "Owner",
    "Environment",
    "CostCenter",
    "Project"
  ]
}

# =============================================================================
# Remediation Configuration
# =============================================================================

variable "enable_auto_remediation" {
  description = "Enable automatic remediation for LOW severity violations"
  type        = bool
  default     = true
}

variable "prod_remediation_allowlist" {
  description = "Resource types allowed for remediation in production"
  type        = list(string)
  default = [
    "AWS::S3::Bucket" # Only S3 public access remediation allowed in prod
  ]
}
