# -----------------------------------------------------------------------------
# Audit Module - DynamoDB Table for Compliance History
# -----------------------------------------------------------------------------
# Stores compliance state changes for historical analysis and auditing.
# Supports TTL for automatic cleanup of old records.
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
