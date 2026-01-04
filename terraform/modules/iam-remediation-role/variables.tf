# -----------------------------------------------------------------------------
# IAM Remediation Role Module - Variables
# -----------------------------------------------------------------------------

variable "role_name" {
  description = "Name of the cross-account remediation role"
  type        = string
  default     = "CloudGovernanceRemediationRole"
}

variable "account_id" {
  description = "AWS account ID where this role is created"
  type        = string
}

variable "governance_lambda_role_arn" {
  description = "ARN of the Lambda execution role in the Governance account that can assume this role"
  type        = string
}

variable "external_id" {
  description = "External ID required for STS AssumeRole (defense in depth)"
  type        = string
  default     = "CloudGovernance-Remediation-2024"
}

variable "is_production" {
  description = "Whether this is a production account (restricts remediation actions)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
