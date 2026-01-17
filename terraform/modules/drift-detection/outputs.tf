# -----------------------------------------------------------------------------
# Drift Detection Module - Outputs
# -----------------------------------------------------------------------------

output "function_arn" {
  description = "ARN of the drift detection Lambda"
  value       = aws_lambda_function.drift_detection.arn
}

output "function_name" {
  description = "Name of the drift detection Lambda"
  value       = aws_lambda_function.drift_detection.function_name
}

output "schedule_rule_arn" {
  description = "ARN of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.drift_schedule.arn
}
