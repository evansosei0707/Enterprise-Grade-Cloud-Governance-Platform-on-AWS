terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "target_account" {
  description = "Target environment to deploy test resources (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.target_account)
    error_message = "Target account must be dev, staging, or prod."
  }
}

# Dynamic provider selection based on variable
# We map lowercase input (dev) to Capitalized Profile (Dev) as per your SSO config
provider "aws" {
  region  = "us-east-1"
  profile = var.target_account == "dev" ? "Dev" : (var.target_account == "staging" ? "Staging" : "Prod")
}

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# 1. Non-Compliant S3 Bucket
# Violation: Public Read ACL, Missing Tags
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "bad_bucket" {
  bucket = "non-compliant-bucket-${var.target_account}-${random_id.suffix.hex}"

  # INTENTIONAL: No tags (Violates required-tags rule)
}

resource "aws_s3_bucket_public_access_block" "bad_bucket" {
  bucket = aws_s3_bucket.bad_bucket.id

  # INTENTIONAL violation: Allow public access
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "bad_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.bad_bucket, aws_s3_bucket_public_access_block.bad_bucket]
  bucket     = aws_s3_bucket.bad_bucket.id
  acl        = "public-read" # INTENTIONAL violation (Violates s3-bucket-public-read-prohibited)
}

resource "aws_s3_bucket_ownership_controls" "bad_bucket" {
  bucket = aws_s3_bucket.bad_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}


# -----------------------------------------------------------------------------
# 2. Non-Compliant Security Group
# Violation: Open SSH (0.0.0.0/0), Open RDP, Missing Tags
# -----------------------------------------------------------------------------
resource "aws_security_group" "bad_sg" {
  name        = "non-compliant-sg-${var.target_account}"
  description = "Security group with open SSH/RDP"

  # INTENTIONAL: No tags
}

resource "aws_security_group_rule" "open_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] # INTENTIONAL violation (Violates restricted-ssh)
  security_group_id = aws_security_group.bad_sg.id
}

resource "aws_security_group_rule" "open_rdp" {
  type              = "ingress"
  from_port         = 3389
  to_port           = 3389
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] # INTENTIONAL violation (Violates restricted-rdp)
  security_group_id = aws_security_group.bad_sg.id
}

# -----------------------------------------------------------------------------
# 3. Non-Compliant EC2 Instance (Mock)
# Violation: Stopped > 7 days (eventually), Missing Tags
# -----------------------------------------------------------------------------
# NOTE: We use a t2.micro and stop it immediately to test 'ec2-stopped-instance' rule logic
# But we won't actually launch a real instance to save cost/time in this demo code.
# The SG and S3 are sufficient for immediate testing. 
