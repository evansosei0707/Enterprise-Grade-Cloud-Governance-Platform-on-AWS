# -----------------------------------------------------------------------------
# Audit Module - DynamoDB Tables for Compliance
# -----------------------------------------------------------------------------
# Stores compliance state changes for historical analysis and auditing.
# Also stores exception whitelist entries.
# -----------------------------------------------------------------------------

# =============================================================================
# Compliance History Table
# =============================================================================

resource "aws_dynamodb_table" "compliance_history" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"  # On-demand for variable workloads
  hash_key     = "pk"               # Partition key: ACCOUNT#<id>#RESOURCE#<id>
  range_key    = "sk"               # Sort key: TIMESTAMP#<ts>

  # Primary key attributes
  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # GSI for querying by rule name
  attribute {
    name = "rule_name"
    type = "S"
  }

  attribute {
    name = "compliance_type"
    type = "S"
  }

  # Global Secondary Index - Query by Rule
  global_secondary_index {
    name            = "rule-index"
    hash_key        = "rule_name"
    range_key       = "sk"
    projection_type = "ALL"
  }

  # Global Secondary Index - Query by Compliance Status
  global_secondary_index {
    name            = "compliance-index"
    hash_key        = "compliance_type"
    range_key       = "sk"
    projection_type = "ALL"
  }

  # TTL for automatic cleanup
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery for disaster recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(var.tags, {
    Purpose = "ComplianceHistory"
  })
}

# =============================================================================
# Compliance Exceptions Table (Whitelist)
# =============================================================================
# Stores exception requests for resources that should be skipped by remediation.
# Supports approval workflow with status field.

resource "aws_dynamodb_table" "compliance_exceptions" {
  name         = "${var.table_name}-exceptions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"  # EXCEPTION#<account_id>#<resource_id>
  range_key    = "sk"  # RULE#<rule_name>

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # GSI for querying by approval status (pending, approved, rejected)
  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "pk"
    projection_type = "ALL"
  }

  # TTL for temporary exceptions (expires_at field)
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(var.tags, {
    Purpose = "ComplianceExceptions"
  })
}

