# -----------------------------------------------------------------------------
# Governance Environment - Control Plane Configuration
# -----------------------------------------------------------------------------
# Deploys the central governance infrastructure:
# - Config Aggregator
# - Audit & Logging (S3, DynamoDB, CloudWatch)
# - Event Pipeline (EventBridge, SNS)
# - Compute (Policy, Remediation, Notification Lambdas)
# -----------------------------------------------------------------------------


module "config_aggregator" {
  source = "../../modules/config-aggregator"

  name_prefix     = local.name_prefix
  organization_id = var.organization_id
  tags            = local.common_tags
}

# Enable Config Recording for Governance Account itself (Self-Monitoring)
module "aws_config" {
  source = "../../modules/aws-config"

  name_prefix                = "${var.project_name}-governance"
  account_id                 = var.governance_account_id
  central_config_bucket_name = local.audit_bucket_name
  central_config_bucket_arn  = "arn:aws:s3:::${local.audit_bucket_name}"
  s3_key_prefix              = null
  include_global_resources   = true # Capture global resources in Governance

  tags = merge(local.common_tags, { Environment = "governance" })
}

# Enable Remediation Role for Governance Account (Self-Remediation)
module "remediation_role" {
  source = "../../modules/iam-remediation-role"

  role_name                  = var.remediation_role_name
  account_id                 = var.governance_account_id
  governance_lambda_role_arn = "arn:aws:iam::${var.governance_account_id}:role/${local.name_prefix}-remediation-engine-role"
  external_id                = "CloudGovernance-Remediation-2024"
  is_production              = true # Treat Governance as Prod for safety
  tags                       = merge(local.common_tags, { Environment = "governance" })
}

module "audit" {
  source = "../../modules/audit"

  name_prefix     = local.name_prefix
  bucket_name     = local.audit_bucket_name
  table_name      = local.compliance_table_name
  organization_id = var.organization_id
  region          = var.primary_region
  tags            = local.common_tags
}

module "notification" {
  source = "../../modules/lambdas/notification"

  name_prefix       = local.name_prefix
  sns_topic_arn     = aws_sns_topic.alerts.arn
  slack_webhook_url = var.slack_webhook_url
  enable_slack      = var.enable_slack
  tags              = local.common_tags
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "evansosei0707@gmail.com"
}

module "remediation_engine" {
  source = "../../modules/lambdas/remediation-engine"

  name_prefix           = local.name_prefix
  remediation_role_name = var.remediation_role_name
  external_id           = "CloudGovernance-Remediation-2024"
  log_level             = "INFO"

  # Account-to-environment mapping for environment-aware tagging
  account_environment_map = {
    (var.governance_account_id) = "governance"
    (var.dev_account_id)        = "dev"
    (var.staging_account_id)    = "staging"
    (var.prod_account_id)       = "prod"
    (var.tooling_account_id)    = "tooling"
  }

  # Production safety: blocks SG remediation in prod
  prod_account_id         = var.prod_account_id
  notification_lambda_arn = module.notification.function_arn

  tags = local.common_tags
}

module "policy_engine" {
  source = "../../modules/lambdas/policy-engine"

  name_prefix             = local.name_prefix
  environment             = "governance"
  dynamodb_table_name     = module.audit.table_name
  dynamodb_table_arn      = module.audit.table_arn
  exceptions_table_name   = module.audit.exceptions_table_name
  exceptions_table_arn    = module.audit.exceptions_table_arn
  remediation_lambda_arn  = module.remediation_engine.function_arn
  notification_lambda_arn = module.notification.function_arn
  log_level               = "INFO"
  tags                    = local.common_tags
}

module "eventbridge" {
  source = "../../modules/eventbridge"

  name_prefix               = local.name_prefix
  policy_engine_lambda_arn  = module.policy_engine.function_arn
  policy_engine_lambda_name = module.policy_engine.function_name
  organization_id           = var.organization_id # Needed for cross-account access
  tags                      = local.common_tags
}

# =============================================================================
# Dashboard API (Path B)
# =============================================================================

module "dashboard_api" {
  source = "../../modules/lambdas/dashboard-api"

  name_prefix           = local.name_prefix
  compliance_table_name = module.audit.table_name
  compliance_table_arn  = module.audit.table_arn
  exceptions_table_name = module.audit.exceptions_table_name
  exceptions_table_arn  = module.audit.exceptions_table_arn
  log_level             = "INFO"
  tags                  = local.common_tags
}

# API Gateway with Custom Domain
module "api_gateway" {
  source = "../../modules/api-gateway"

  name_prefix          = local.name_prefix
  domain_name          = var.api_domain_name
  hosted_zone_id       = var.hosted_zone_id
  lambda_invoke_arn    = module.dashboard_api.invoke_arn
  lambda_function_name = module.dashboard_api.function_name
  stage_name           = "v1"
  tags                 = local.common_tags
}

# Drift Detection (Daily at 7pm UTC)
module "drift_detection" {
  source = "../../modules/drift-detection"

  name_prefix             = local.name_prefix
  tf_state_bucket         = local.tf_state_bucket
  tf_state_key            = "governance/terraform.tfstate"
  notification_lambda_arn = module.notification.function_arn
  schedule_expression     = "cron(0 19 * * ? *)" # 7pm UTC daily
  log_level               = "INFO"
  tags                    = local.common_tags
}
