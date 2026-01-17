# -----------------------------------------------------------------------------
# API Gateway Module - Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "domain_name" {
  description = "Custom domain name for API (e.g., api.my-projects-aws.site)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID for the domain"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "Invoke ARN of the Dashboard API Lambda"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Dashboard API Lambda function"
  type        = string
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "v1"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
