# -----------------------------------------------------------------------------
# AWS Config Module - Config Rules
# -----------------------------------------------------------------------------
# Defines compliance rules for tagging, security, and cost optimization.
# -----------------------------------------------------------------------------

# =============================================================================
# Tagging Rules
# =============================================================================

resource "aws_config_config_rule" "required_tags" {
  name        = "required-tags"
  description = "Checks if required tags are present on resources"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = "Owner"
    tag2Key = "Environment"
    tag3Key = "CostCenter"
    tag4Key = "Project"
  })

  scope {
    compliance_resource_types = var.tagging_resource_types
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = var.tags
}

# =============================================================================
# Security Rules - S3
# =============================================================================

resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  name        = "s3-bucket-public-read-prohibited"
  description = "Checks if S3 buckets do not allow public read access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  scope {
    compliance_resource_types = ["AWS::S3::Bucket"]
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = var.tags
}

resource "aws_config_config_rule" "s3_bucket_public_write_prohibited" {
  name        = "s3-bucket-public-write-prohibited"
  description = "Checks if S3 buckets do not allow public write access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
  }

  scope {
    compliance_resource_types = ["AWS::S3::Bucket"]
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = var.tags
}

# =============================================================================
# Security Rules - Network
# =============================================================================

resource "aws_config_config_rule" "restricted_ssh" {
  name        = "restricted-ssh"
  description = "Checks if security groups allow unrestricted SSH access (0.0.0.0/0 on port 22)"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  scope {
    compliance_resource_types = ["AWS::EC2::SecurityGroup"]
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = var.tags
}

resource "aws_config_config_rule" "restricted_rdp" {
  name        = "restricted-rdp"
  description = "Checks if security groups allow unrestricted RDP access (0.0.0.0/0 on port 3389)"

  source {
    owner             = "AWS"
    source_identifier = "RESTRICTED_INCOMING_TRAFFIC"
  }

  input_parameters = jsonencode({
    blockedPort1 = "3389"
  })

  scope {
    compliance_resource_types = ["AWS::EC2::SecurityGroup"]
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = var.tags
}

# =============================================================================
# Cost Hygiene Rules (Detect Only - No Auto-Remediation)
# =============================================================================

# Note: This is a custom Lambda rule for detecting underutilized EC2 instances
# For simplicity, we use the AWS managed rule that checks for stopped instances
# A more sophisticated CloudWatch-based check would require a custom Lambda

resource "aws_config_config_rule" "ec2_stopped_instance" {
  count = var.enable_cost_rules ? 1 : 0

  name        = "ec2-stopped-instance"
  description = "Detects EC2 instances that have been stopped for extended periods"

  source {
    owner             = "AWS"
    source_identifier = "EC2_STOPPED_INSTANCE"
  }

  input_parameters = jsonencode({
    AllowedDays = "7"
  })

  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = merge(var.tags, {
    RemediationType = "DETECT_ONLY"
  })
}
