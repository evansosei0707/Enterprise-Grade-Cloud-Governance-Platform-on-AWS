# -----------------------------------------------------------------------------
# CI/CD Pipeline Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository URL (e.g., https://github.com/owner/repo)"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch to track"
  type        = string
  default     = "main"
}

variable "governance_account_id" {
  description = "Governance account ID"
  type        = string
}

variable "dev_account_id" {
  description = "Dev account ID"
  type        = string
}

variable "staging_account_id" {
  description = "Staging account ID"
  type        = string
}

variable "prod_account_id" {
  description = "Prod account ID"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "notification_topic_arn" {
  description = "SNS topic ARN for pipeline notifications"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
