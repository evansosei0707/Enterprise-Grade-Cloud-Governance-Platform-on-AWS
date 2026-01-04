# -----------------------------------------------------------------------------
# Audit Module - Outputs
# -----------------------------------------------------------------------------

output "bucket_arn" {
  description = "ARN of the audit S3 bucket"
  value       = aws_s3_bucket.audit.arn
}

output "bucket_name" {
  description = "Name of the audit S3 bucket"
  value       = aws_s3_bucket.audit.id
}

output "table_arn" {
  description = "ARN of the DynamoDB compliance history table"
  value       = aws_dynamodb_table.compliance_history.arn
}

output "table_name" {
  description = "Name of the DynamoDB compliance history table"
  value       = aws_dynamodb_table.compliance_history.id
}

output "log_group_arns" {
  description = "ARNs of the CloudWatch log groups"
  value = {
    policy_engine      = aws_cloudwatch_log_group.policy_engine.arn
    remediation_engine = aws_cloudwatch_log_group.remediation_engine.arn
    notification       = aws_cloudwatch_log_group.notification.arn
  }
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.governance.dashboard_name
}
