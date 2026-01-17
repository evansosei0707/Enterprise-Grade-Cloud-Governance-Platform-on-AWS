# -----------------------------------------------------------------------------
# EventBridge Module - Rules for Config Compliance Events
# -----------------------------------------------------------------------------
# Creates EventBridge rules to capture AWS Config compliance change events
# and route them to the Policy Engine Lambda for processing.
# -----------------------------------------------------------------------------

# =============================================================================
# EventBridge Rule - Config Compliance Changes
# =============================================================================

resource "aws_cloudwatch_event_rule" "config_compliance" {
  name        = "${var.name_prefix}-config-compliance"
  description = "Captures AWS Config compliance change notifications"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      messageType = ["ComplianceChangeNotification"]
    }
  })

  tags = var.tags
}

# =============================================================================
# EventBridge Target - Policy Engine Lambda
# =============================================================================

resource "aws_cloudwatch_event_target" "policy_engine" {
  rule      = aws_cloudwatch_event_rule.config_compliance.name
  target_id = "policy-engine-lambda"
  arn       = var.policy_engine_lambda_arn

  # Retry policy for failed invocations
  retry_policy {
    maximum_event_age_in_seconds = 3600 # 1 hour
    maximum_retry_attempts       = 3
  }

  # Dead letter queue for failed events
  dead_letter_config {
    arn = var.dead_letter_queue_arn
  }
}

# =============================================================================
# Lambda Permission for EventBridge Invocation
# =============================================================================

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.policy_engine_lambda_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_compliance.arn
}

# =============================================================================
# IAM Role for EventBridge (if needed for cross-account)
# =============================================================================

resource "aws_iam_role" "eventbridge" {
  count = var.create_eventbridge_role ? 1 : 0

  name               = "${var.name_prefix}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "eventbridge_assume" {
  count = var.create_eventbridge_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# =============================================================================
# Event Bus Policy - Allow Organization Access
# =============================================================================

resource "aws_cloudwatch_event_bus_policy" "org_access" {
  count = var.organization_id != null ? 1 : 0

  policy         = data.aws_iam_policy_document.event_bus_org_access[0].json
  event_bus_name = "default"
}

data "aws_iam_policy_document" "event_bus_org_access" {
  count = var.organization_id != null ? 1 : 0

  statement {
    sid    = "AllowOrganizationPutEvents"
    effect = "Allow"
    actions = [
      "events:PutEvents"
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      "arn:aws:events:us-east-1:257016720202:event-bus/default"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}
