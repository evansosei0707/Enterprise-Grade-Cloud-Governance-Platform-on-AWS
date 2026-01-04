# -----------------------------------------------------------------------------
# AWS Config Module - Input Variables
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "account_id" {
  description = "The AWS account ID where Config is being enabled"
  type        = string
}

variable "central_config_bucket_name" {
  description = "Name of the centralized S3 bucket for Config data"
  type        = string
}

variable "governance_event_bus_arn" {
  description = "ARN of the Governance account's default event bus for forwarding events"
  type        = string
  default     = null
}

variable "central_config_bucket_arn" {
  description = "ARN of the centralized S3 bucket for Config data"
  type        = string
}

variable "s3_key_prefix" {
  description = "Prefix for the S3 bucket. Config Service appends 'AWSLogs/<account_id>/Config'. Set to null for default."
  type        = string
  default     = null
}

variable "include_global_resources" {
  description = "Whether to include global resources like IAM in recording"
  type        = bool
  default     = true
}

variable "snapshot_frequency" {
  description = "Frequency of configuration snapshot delivery"
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition     = contains(["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"], var.snapshot_frequency)
    error_message = "snapshot_frequency must be one of: One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours"
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for Config notifications (optional)"
  type        = string
  default     = null
}

variable "tagging_resource_types" {
  description = "Resource types to check for required tags"
  type        = list(string)
  default = [
    "AWS::EC2::Instance",
    "AWS::S3::Bucket",
    "AWS::RDS::DBInstance",
    "AWS::Lambda::Function",
    "AWS::DynamoDB::Table"
  ]
}

variable "enable_cost_rules" {
  description = "Enable cost optimization detection rules"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
