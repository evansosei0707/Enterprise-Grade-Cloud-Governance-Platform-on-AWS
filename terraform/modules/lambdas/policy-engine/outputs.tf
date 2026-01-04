# -----------------------------------------------------------------------------
# Policy Engine Lambda Module - Outputs
# -----------------------------------------------------------------------------

output "function_arn" {
  description = "ARN of the Policy Engine Lambda function"
  value       = aws_lambda_function.policy_engine.arn
}

output "function_name" {
  description = "Name of the Policy Engine Lambda function"
  value       = aws_lambda_function.policy_engine.function_name
}

output "role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.policy_engine.arn
}

output "role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.policy_engine.name
}
