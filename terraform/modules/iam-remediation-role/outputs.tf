# -----------------------------------------------------------------------------
# IAM Remediation Role Module - Outputs
# -----------------------------------------------------------------------------

output "role_arn" {
  description = "ARN of the cross-account remediation role"
  value       = aws_iam_role.remediation.arn
}

output "role_name" {
  description = "Name of the cross-account remediation role"
  value       = aws_iam_role.remediation.name
}

output "role_id" {
  description = "ID of the cross-account remediation role"
  value       = aws_iam_role.remediation.id
}
