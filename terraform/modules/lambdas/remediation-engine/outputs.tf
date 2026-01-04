# -----------------------------------------------------------------------------
# Remediation Engine Lambda Module - Outputs
# -----------------------------------------------------------------------------

output "function_arn" {
  description = "ARN of the Remediation Engine Lambda function"
  value       = aws_lambda_function.remediation_engine.arn
}

output "function_name" {
  description = "Name of the Remediation Engine Lambda function"
  value       = aws_lambda_function.remediation_engine.function_name
}
