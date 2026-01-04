# -----------------------------------------------------------------------------
# IAM Remediation Role Module - Main Configuration
# -----------------------------------------------------------------------------
# Creates cross-account IAM role in member accounts that allows the
# Governance account's Lambda functions to perform safe remediation actions.
# -----------------------------------------------------------------------------

# =============================================================================
# Cross-Account Remediation Role
# =============================================================================

resource "aws_iam_role" "remediation" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.remediation_trust.json
  description        = "Allows Governance account Lambda to perform safe remediation actions"

  tags = var.tags
}

# =============================================================================
# Trust Policy - Only Governance Account Lambda
# =============================================================================

data "aws_iam_policy_document" "remediation_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.governance_lambda_role_arn]
    }

    # Additional security: require external ID for defense in depth
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

# =============================================================================
# Remediation Permissions - Scoped and Safe
# =============================================================================

resource "aws_iam_role_policy" "remediation_actions" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.remediation.id
  policy = data.aws_iam_policy_document.remediation_actions.json
}

data "aws_iam_policy_document" "remediation_actions" {
  # S3 Public Access Remediation
  statement {
    sid    = "S3PublicAccessRemediation"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl",
      "s3:PutBucketAcl",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketPolicy",
      "s3:DeleteBucketPolicy"
    ]
    resources = ["arn:aws:s3:::*"]

    # Only allow actions on buckets in this account
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [var.account_id]
    }
  }

  # Tagging Remediation
  statement {
    sid    = "TaggingRemediation"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "s3:PutBucketTagging",
      "rds:AddTagsToResource",
      "lambda:TagResource",
      "dynamodb:TagResource"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [var.account_id]
    }
  }

  # Security Group Remediation (Revoke only - no delete)
  statement {
    sid    = "SecurityGroupRemediation"
    effect = "Allow"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:RevokeSecurityGroupIngress"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [var.account_id]
    }
  }

  # Read-only for resource discovery
  statement {
    sid    = "ReadOnlyDiscovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "s3:ListAllMyBuckets",
      "s3:GetBucketTagging",
      "config:GetResourceConfigHistory",
      "config:GetComplianceDetailsByConfigRule"
    ]
    resources = ["*"]
  }
}
