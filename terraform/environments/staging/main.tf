# -----------------------------------------------------------------------------
# Staging Environment - Member Account Configuration
# -----------------------------------------------------------------------------
# Same configuration as Dev, applied to Staging account.
# -----------------------------------------------------------------------------


module "aws_config" {
  source = "../../modules/aws-config"
  providers = {
    aws = aws.staging
  }

  name_prefix                = "${var.project_name}-staging"
  account_id                 = var.staging_account_id
  central_config_bucket_name = "cloud-governance-audit-${var.governance_account_id}"
  central_config_bucket_arn  = "arn:aws:s3:::cloud-governance-audit-${var.governance_account_id}"
  governance_event_bus_arn   = "arn:aws:events:us-east-1:257016720202:event-bus/default"
  s3_key_prefix              = null
  include_global_resources   = false

  tags = merge(local.common_tags, { Environment = "staging" })
}

module "remediation_role" {
  source = "../../modules/iam-remediation-role"
  providers = {
    aws = aws.staging
  }

  role_name                  = var.remediation_role_name
  account_id                 = var.staging_account_id
  governance_lambda_role_arn = "arn:aws:iam::${var.governance_account_id}:role/${local.name_prefix}-remediation-engine-role"
  external_id                = "CloudGovernance-Remediation-2024"
  is_production              = false
  tags                       = merge(local.common_tags, { Environment = "staging" })
}
