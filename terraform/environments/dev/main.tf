# -----------------------------------------------------------------------------
# Dev Environment - Member Account Configuration
# -----------------------------------------------------------------------------
# Deploys standard governance controls to the Dev account:
# - AWS Config Recorder & Rules
# - Cross-Account Remediation Role
# -----------------------------------------------------------------------------


module "aws_config" {
  source = "../../modules/aws-config"
  providers = {
    aws = aws.dev
  }

  name_prefix                = "${var.project_name}-dev"
  account_id                 = var.dev_account_id
  central_config_bucket_name = "cloud-governance-audit-${var.governance_account_id}"
  central_config_bucket_arn  = "arn:aws:s3:::cloud-governance-audit-${var.governance_account_id}"
  governance_event_bus_arn   = "arn:aws:events:us-east-1:257016720202:event-bus/default"
  s3_key_prefix              = null # Config Service automatically appends AWSLogs/<account_id>/Config

  
  include_global_resources = false # Only capture global in one account (Governance/Prod) usually, or all if desired.
                                   # Here we disable for Dev to reduce noise/cost, or enable if strictly required.
                                   # Let's keep false for Dev, true for Prod/Governance.

  tags = merge(local.common_tags, { Environment = "dev" })
}

module "remediation_role" {
  source = "../../modules/iam-remediation-role"
  providers = {
    aws = aws.dev
  }

  role_name                  = var.remediation_role_name
  account_id                 = var.dev_account_id
  governance_lambda_role_arn = "arn:aws:iam::${var.governance_account_id}:role/${local.name_prefix}-remediation-engine-role"
  external_id                = "CloudGovernance-Remediation-2024"
  is_production              = false
  tags                       = merge(local.common_tags, { Environment = "dev" })
}
