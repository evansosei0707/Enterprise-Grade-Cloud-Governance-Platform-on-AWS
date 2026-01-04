# -----------------------------------------------------------------------------
# EventBridge Module - Outputs
# -----------------------------------------------------------------------------

output "rule_arn" {
  description = "ARN of the Config compliance EventBridge rule"
  value       = aws_cloudwatch_event_rule.config_compliance.arn
}

output "rule_name" {
  description = "Name of the Config compliance EventBridge rule"
  value       = aws_cloudwatch_event_rule.config_compliance.name
}
