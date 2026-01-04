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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
