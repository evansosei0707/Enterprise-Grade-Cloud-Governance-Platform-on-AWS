# Outputs for the root module
# These expose key values for use by other configurations

output "organization_id" {
  description = "AWS Organization ID"
  value       = var.organization_id
}

output "governance_account_id" {
  description = "Governance account ID hosting the control plane"
  value       = var.governance_account_id
}

output "workload_account_ids" {
  description = "Map of workload environment names to account IDs"
  value       = local.workload_accounts
}

output "config_bucket_name" {
  description = "S3 bucket name for AWS Config delivery"
  value       = local.config_bucket_name
}

output "audit_bucket_name" {
  description = "S3 bucket name for audit logs"
  value       = local.audit_bucket_name
}
