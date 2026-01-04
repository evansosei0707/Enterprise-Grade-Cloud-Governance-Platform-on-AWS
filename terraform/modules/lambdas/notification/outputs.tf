# -----------------------------------------------------------------------------
# Notification Lambda Module - Outputs
# -----------------------------------------------------------------------------

output "function_arn" {
  description = "ARN of the Notification Lambda function"
  value       = aws_lambda_function.notification.arn
}
