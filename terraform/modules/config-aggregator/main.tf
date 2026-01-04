# -----------------------------------------------------------------------------
# Config Aggregator Module - Main Configuration
# -----------------------------------------------------------------------------
# Creates an organization-wide Config Aggregator in the Governance account
# to provide centralized visibility of compliance across all member accounts.
# -----------------------------------------------------------------------------

# =============================================================================
# Organization-Wide Config Aggregator
# =============================================================================

resource "aws_config_configuration_aggregator" "org" {
  name = "${var.name_prefix}-org-aggregator"

  organization_aggregation_source {
    # Use organization as the source - NOT individual account list
    all_regions = true
    role_arn    = aws_iam_role.aggregator.arn
  }

  tags = var.tags
}

# =============================================================================
# IAM Role for Config Aggregator
# =============================================================================

resource "aws_iam_role" "aggregator" {
  name               = "${var.name_prefix}-config-aggregator-role"
  assume_role_policy = data.aws_iam_policy_document.aggregator_assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "aggregator_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

# =============================================================================
# IAM Policy for Organization Read Access
# =============================================================================

resource "aws_iam_role_policy" "aggregator_org_access" {
  name   = "${var.name_prefix}-aggregator-org-access"
  role   = aws_iam_role.aggregator.id
  policy = data.aws_iam_policy_document.aggregator_org_access.json
}

data "aws_iam_policy_document" "aggregator_org_access" {
  statement {
    sid    = "AllowOrganizationsRead"
    effect = "Allow"
    actions = [
      "organizations:ListAccounts",
      "organizations:DescribeOrganization",
      "organizations:DescribeAccount",
      "organizations:ListAWSServiceAccessForOrganization",
      "organizations:ListDelegatedAdministrators"
    ]
    resources = ["*"]
  }
}
