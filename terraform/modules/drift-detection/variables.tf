# -----------------------------------------------------------------------------
# Drift Detection Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket containing Terraform state files"
  type        = string
}

variable "tf_state_key" {
  description = "S3 key for the Terraform state file"
  type        = string
  default     = "governance/terraform.tfstate"
}

variable "notification_lambda_arn" {
  description = "ARN of the notification Lambda for drift alerts"
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for drift detection"
  type        = string
  default     = "cron(0 19 * * ? *)" # 7pm UTC daily
}

variable "log_level" {
  description = "Logging level for Lambda"
  type        = string
  default     = "INFO"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
