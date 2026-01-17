# -----------------------------------------------------------------------------
# Remediation Engine Lambda Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "remediation_role_name" {
  description = "Name of the cross-account remediation role to assume"
  type        = string
}

variable "external_id" {
  description = "External ID to use when assuming the role"
  type        = string
}

variable "log_level" {
  description = "Logging level"
  type        = string
  default     = "INFO"
}

variable "account_environment_map" {
  description = "Map of account IDs to environment names (e.g., dev, staging, prod, governance, tooling)"
  type        = map(string)
  default     = {}
}

variable "prod_account_id" {
  description = "Production account ID for safety checks (blocks SG remediation in prod)"
  type        = string
  default     = ""
}

variable "notification_lambda_arn" {
  description = "ARN of the notification Lambda for prod safety fallback"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

