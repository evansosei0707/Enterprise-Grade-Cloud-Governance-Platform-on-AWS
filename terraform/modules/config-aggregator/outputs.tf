# -----------------------------------------------------------------------------
# Config Aggregator Module - Outputs
# -----------------------------------------------------------------------------

output "aggregator_arn" {
  description = "ARN of the Config Aggregator"
  value       = aws_config_configuration_aggregator.org.arn
}

output "aggregator_name" {
  description = "Name of the Config Aggregator"
  value       = aws_config_configuration_aggregator.org.name
}

output "aggregator_role_arn" {
  description = "ARN of the IAM role used by the Aggregator"
  value       = aws_iam_role.aggregator.arn
}
