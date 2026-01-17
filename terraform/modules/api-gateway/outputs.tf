# -----------------------------------------------------------------------------
# API Gateway Module - Outputs
# -----------------------------------------------------------------------------

output "api_id" {
  description = "ID of the REST API"
  value       = aws_api_gateway_rest_api.governance.id
}

output "api_endpoint" {
  description = "Default API endpoint URL"
  value       = aws_api_gateway_stage.governance.invoke_url
}

output "custom_domain_url" {
  description = "Custom domain URL for the API"
  value       = "https://${var.domain_name}"
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.api.arn
}
