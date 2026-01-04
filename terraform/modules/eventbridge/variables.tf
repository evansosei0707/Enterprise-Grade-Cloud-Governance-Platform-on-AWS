# -----------------------------------------------------------------------------
# EventBridge Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "policy_engine_lambda_arn" {
  description = "ARN of the Policy Engine Lambda function"
  type        = string
}

variable "policy_engine_lambda_name" {
  description = "Name of the Policy Engine Lambda function"
  type        = string
}

variable "organization_id" {
  description = "The AWS Organization ID to allow cross-account events from"
  type        = string
  default     = null
}

variable "dead_letter_queue_arn" {
  description = "ARN of the SQS dead letter queue for failed events"
  type        = string
  default     = null
}

variable "create_eventbridge_role" {
  description = "Whether to create an IAM role for EventBridge"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
