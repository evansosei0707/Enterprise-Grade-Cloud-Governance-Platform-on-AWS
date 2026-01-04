# -----------------------------------------------------------------------------
# Policy Engine Lambda Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (governance, dev, staging, prod)"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB compliance history table"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB compliance history table"
  type        = string
}

variable "remediation_lambda_arn" {
  description = "ARN of the remediation Lambda function"
  type        = string
  default     = ""
}

variable "notification_lambda_arn" {
  description = "ARN of the notification Lambda function"
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Logging level for Lambda (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
}

variable "vpc_config" {
  description = "VPC configuration for Lambda (optional)"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
