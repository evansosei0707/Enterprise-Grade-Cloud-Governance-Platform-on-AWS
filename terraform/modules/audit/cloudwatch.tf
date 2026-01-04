# -----------------------------------------------------------------------------
# Audit Module - CloudWatch Resources
# -----------------------------------------------------------------------------
# Creates CloudWatch dashboards, log groups, and alarms for monitoring
# the governance platform.
# -----------------------------------------------------------------------------

# =============================================================================
# Log Groups for Lambda Functions
# =============================================================================

resource "aws_cloudwatch_log_group" "policy_engine" {
  name              = "/aws/lambda/${var.name_prefix}-policy-engine"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "remediation_engine" {
  name              = "/aws/lambda/${var.name_prefix}-remediation-engine"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "notification" {
  name              = "/aws/lambda/${var.name_prefix}-notification"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "governance" {
  dashboard_name = "${var.name_prefix}-governance-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Config Compliance Events"
          region = var.region
          metrics = [
            ["AWS/Events", "Invocations", "RuleName", "${var.name_prefix}-config-compliance"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Policy Engine Lambda Invocations"
          region = var.region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name_prefix}-policy-engine"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name_prefix}-policy-engine"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Remediation Actions"
          region = var.region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name_prefix}-remediation-engine"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name_prefix}-remediation-engine"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB Operations"
          region = var.region
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.table_name],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.table_name]
          ]
          period = 300
          stat   = "Sum"
        }
      }
    ]
  })
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda errors exceeded threshold"

  dimensions = {
    FunctionName = "${var.name_prefix}-policy-engine"
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count = var.enable_alarms && var.dlq_name != null ? 1 : 0

  alarm_name          = "${var.name_prefix}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages in DLQ indicate failed processing"

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}
