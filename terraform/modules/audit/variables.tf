# -----------------------------------------------------------------------------
# Audit Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "bucket_name" {
  description = "Name of the audit S3 bucket"
  type        = string
}

variable "table_name" {
  description = "Name of the DynamoDB compliance history table"
  type        = string
}

variable "organization_id" {
  description = "AWS Organization ID for bucket policy"
  type        = string
}

variable "region" {
  description = "AWS region for CloudWatch dashboard"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption (optional)"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 90
}

variable "enable_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
  default     = null
}

variable "dlq_name" {
  description = "Name of the DLQ for SQS alarm"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
