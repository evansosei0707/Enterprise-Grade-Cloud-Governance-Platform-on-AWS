# -----------------------------------------------------------------------------
# Dashboard API Lambda Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "compliance_table_name" {
  description = "Name of the DynamoDB compliance history table"
  type        = string
}

variable "compliance_table_arn" {
  description = "ARN of the DynamoDB compliance history table"
  type        = string
}

variable "exceptions_table_name" {
  description = "Name of the DynamoDB compliance exceptions table"
  type        = string
}

variable "exceptions_table_arn" {
  description = "ARN of the DynamoDB compliance exceptions table"
  type        = string
}

variable "log_level" {
  description = "Logging level for Lambda (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
