# -----------------------------------------------------------------------------
# AWS Config Module - Delivery Channel
# -----------------------------------------------------------------------------
# Configures the delivery channel to send Config data to the central
# S3 bucket in the Governance account.
# -----------------------------------------------------------------------------

resource "aws_config_delivery_channel" "main" {
  name           = "${var.name_prefix}-delivery-channel"
  s3_bucket_name = var.central_config_bucket_name
  s3_key_prefix  = var.s3_key_prefix

  # Configure snapshot delivery frequency
  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_frequency
  }

  # SNS topic for notifications (optional)
  sns_topic_arn = var.sns_topic_arn

  depends_on = [aws_config_configuration_recorder.main]
}
