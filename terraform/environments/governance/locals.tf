# -----------------------------------------------------------------------------
# Local Values for Cloud Governance Platform
# -----------------------------------------------------------------------------
# Computed values and mappings used throughout the Terraform configuration.
# -----------------------------------------------------------------------------

locals {
  # =========================================================================
  # Account Mappings
  # =========================================================================

  # Map of all member accounts (excludes management)
  member_accounts = {
    governance = var.governance_account_id
    dev        = var.dev_account_id
    staging    = var.staging_account_id
    prod       = var.prod_account_id
  }

  # Map of workload accounts (excludes management and governance)
  workload_accounts = {
    dev     = var.dev_account_id
    staging = var.staging_account_id
    prod    = var.prod_account_id
  }

  # Non-production accounts (safe for aggressive remediation)
  non_prod_accounts = {
    dev     = var.dev_account_id
    staging = var.staging_account_id
  }

  # =========================================================================
  # Resource Naming
  # =========================================================================

  # Standard naming prefix
  name_prefix = "${var.project_name}-${var.environment}"

  # S3 bucket names (must be globally unique)
  config_bucket_name = "${var.project_name}-config-${var.governance_account_id}"
  audit_bucket_name  = "${var.project_name}-audit-${var.governance_account_id}"

  # DynamoDB table names
  compliance_table_name = "${var.project_name}-compliance-history"
  terraform_lock_table  = "${var.project_name}-terraform-locks"

  # Terraform state bucket (for drift detection)
  tf_state_bucket = "${var.project_name}-terraform-state-${var.governance_account_id}"

  # =========================================================================
  # IAM ARNs
  # =========================================================================

  # Governance account Lambda execution role ARN pattern
  lambda_role_arn_prefix = "arn:aws:iam::${var.governance_account_id}:role/${local.name_prefix}"

  # Cross-account remediation role ARNs
  remediation_role_arns = {
    for env, account_id in local.workload_accounts :
    env => "arn:aws:iam::${account_id}:role/${var.remediation_role_name}"
  }

  # =========================================================================
  # Config Rules Configuration
  # =========================================================================

  # Tagging rules configuration
  tagging_rules = {
    required_tags = {
      tag_keys = var.required_tags
      resource_types = [
        "AWS::EC2::Instance",
        "AWS::S3::Bucket",
        "AWS::RDS::DBInstance",
        "AWS::Lambda::Function",
        "AWS::DynamoDB::Table",
        "AWS::ECS::Cluster",
        "AWS::EKS::Cluster"
      ]
    }
  }

  # Security rules configuration
  security_rules = {
    s3_public_read  = "s3-bucket-public-read-prohibited"
    s3_public_write = "s3-bucket-public-write-prohibited"
    restricted_ssh  = "restricted-ssh"
    restricted_rdp  = "restricted-common-ports"
  }

  # =========================================================================
  # Severity Classification
  # =========================================================================

  # Map Config rule names to severity levels
  rule_severity = {
    # LOW - Auto-remediate
    "required-tags"                    = "LOW"
    "s3-bucket-public-read-prohibited" = "LOW"

    # MEDIUM - Notify
    "s3-bucket-public-write-prohibited" = "MEDIUM"
    "restricted-ssh"                    = "MEDIUM"
    "restricted-common-ports"           = "MEDIUM"

    # HIGH - Log only (manual review required)
    "ec2-instance-managed-by-ssm" = "HIGH"
    "iam-user-mfa-enabled"        = "HIGH"
  }

  # =========================================================================
  # EventBridge Patterns
  # =========================================================================

  config_compliance_event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      messageType = ["ComplianceChangeNotification"]
    }
  })

  # =========================================================================
  # Common Tags with Environment Override
  # =========================================================================

  common_tags = merge(var.default_tags, {
    Environment = var.environment
    UpdatedAt   = timestamp()
  })
}
