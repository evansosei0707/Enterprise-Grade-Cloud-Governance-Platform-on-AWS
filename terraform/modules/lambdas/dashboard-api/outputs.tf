# -----------------------------------------------------------------------------
# Dashboard API Lambda Module - Outputs
# -----------------------------------------------------------------------------

output "function_arn" {
  description = "ARN of the Dashboard API Lambda function"
  value       = aws_lambda_function.dashboard_api.arn
}

output "function_name" {
  description = "Name of the Dashboard API Lambda function"
  value       = aws_lambda_function.dashboard_api.function_name
}

output "invoke_arn" {
  description = "Invoke ARN for API Gateway integration"
  value       = aws_lambda_function.dashboard_api.invoke_arn
}
