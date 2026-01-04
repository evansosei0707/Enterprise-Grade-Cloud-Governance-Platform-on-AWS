# -----------------------------------------------------------------------------
# Audit Module - S3 Bucket for Audit Logs
# -----------------------------------------------------------------------------
# Creates a secure S3 bucket for storing audit logs and Config snapshots
# with versioning, encryption, and lifecycle policies.
# -----------------------------------------------------------------------------

# =============================================================================
# S3 Bucket for Audit Logs
# =============================================================================

resource "aws_s3_bucket" "audit" {
  bucket = var.bucket_name

  tags = merge(var.tags, {
    Purpose = "AuditLogs"
  })
}

# =============================================================================
# Bucket Versioning
# =============================================================================

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# Server-Side Encryption
# =============================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

# =============================================================================
# Block Public Access
# =============================================================================

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# Lifecycle Policy - Archive Old Logs
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 730  # 2 years
    }
  }
}

# =============================================================================
# Bucket Policy - Allow Config Delivery from Member Accounts
# =============================================================================

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = data.aws_iam_policy_document.audit_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.audit]
}

data "aws_iam_policy_document" "audit_bucket_policy" {
  # Allow Config service to write from any org account
  statement {
    sid    = "AllowConfigDelivery"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = ["${aws_s3_bucket.audit.arn}/AWSLogs/*/Config/*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values   = [var.organization_id]
    }
  }

  # Allow Config service to check bucket ACL
  statement {
    sid    = "AllowConfigBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl",
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.audit.arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }

  # Enforce HTTPS only
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.audit.arn,
      "${aws_s3_bucket.audit.arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
