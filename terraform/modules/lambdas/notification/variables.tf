# -----------------------------------------------------------------------------
# Notification Lambda Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic to publish notifications to"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack Incoming Webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_slack" {
  description = "Enable Slack notifications"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

