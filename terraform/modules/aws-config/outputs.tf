# -----------------------------------------------------------------------------
# AWS Config Module - Outputs
# -----------------------------------------------------------------------------

output "configuration_recorder_id" {
  description = "ID of the configuration recorder"
  value       = aws_config_configuration_recorder.main.id
}

output "configuration_recorder_name" {
  description = "Name of the configuration recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "delivery_channel_id" {
  description = "ID of the delivery channel"
  value       = aws_config_delivery_channel.main.id
}

output "config_role_arn" {
  description = "ARN of the IAM role used by AWS Config"
  value       = aws_iam_role.config.arn
}

output "config_rule_arns" {
  description = "Map of Config rule names to ARNs"
  value = {
    required_tags                    = aws_config_config_rule.required_tags.arn
    s3_bucket_public_read_prohibited = aws_config_config_rule.s3_bucket_public_read_prohibited.arn
    s3_bucket_public_write_prohibited = aws_config_config_rule.s3_bucket_public_write_prohibited.arn
    restricted_ssh                   = aws_config_config_rule.restricted_ssh.arn
    restricted_rdp                   = aws_config_config_rule.restricted_rdp.arn
  }
}
