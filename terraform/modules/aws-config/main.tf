# -----------------------------------------------------------------------------
# AWS Config Module - Main Configuration
# -----------------------------------------------------------------------------
# Enables AWS Config in member accounts with configuration recorder,
# IAM role, and delivery channel to centralized S3 bucket.
# -----------------------------------------------------------------------------

# =============================================================================
# Configuration Recorder
# =============================================================================

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.name_prefix}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported = true

    # Include global resources (IAM, CloudFront, etc.)
    include_global_resource_types = var.include_global_resources

    recording_strategy {
      use_only = "ALL_SUPPORTED_RESOURCE_TYPES"
    }
  }
}

# =============================================================================
# Configuration Recorder Status (Start the recorder)
# =============================================================================

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  # Delivery channel must exist before starting recorder
  depends_on = [aws_config_delivery_channel.main]
}

# =============================================================================
# IAM Role for AWS Config
# =============================================================================

resource "aws_iam_role" "config" {
  name               = "${var.name_prefix}-config-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "config_assume_role" {
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
# IAM Policy Attachments
# =============================================================================

# AWS managed policy for Config service
resource "aws_iam_role_policy_attachment" "config_service" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Custom policy for S3 delivery to central bucket
resource "aws_iam_role_policy" "config_s3_delivery" {
  name   = "${var.name_prefix}-config-s3-delivery"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.config_s3_delivery.json
}

data "aws_iam_policy_document" "config_s3_delivery" {
  # Allow putting config snapshots and history to central bucket
  statement {
    sid    = "AllowS3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = [
      "${var.central_config_bucket_arn}/AWSLogs/${var.account_id}/Config/*"
    ]

    condition {
      test     = "StringLike"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "AllowS3BucketLocation"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl",
      "s3:ListBucket"
    ]
    resources = [var.central_config_bucket_arn]
  }
}
