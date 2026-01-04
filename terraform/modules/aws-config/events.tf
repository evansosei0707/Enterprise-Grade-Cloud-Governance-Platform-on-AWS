# -----------------------------------------------------------------------------
# EventBridge Forwarding - Config Compliance Events
# -----------------------------------------------------------------------------
# Forwards "Config Rules Compliance Change" events to the centralized
# Governance account's default EventBus.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "forward_compliance" {
  count = var.governance_event_bus_arn != null ? 1 : 0

  name        = "${var.name_prefix}-forward-compliance"
  description = "Forwards Config compliance events to Governance account"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      messageType = ["ComplianceChangeNotification"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "governance_bus" {
  count = var.governance_event_bus_arn != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.forward_compliance[0].name
  target_id = "GovernanceEventBus"
  arn       = var.governance_event_bus_arn
  role_arn  = aws_iam_role.event_forwarder[0].arn
}

# -----------------------------------------------------------------------------
# IAM Role for EventBridge Target
# -----------------------------------------------------------------------------
# EventBridge needs permission to PutEvents to another account's EventBus.

resource "aws_iam_role" "event_forwarder" {
  count = var.governance_event_bus_arn != null ? 1 : 0

  name               = "${var.name_prefix}-event-forwarder"
  assume_role_policy = data.aws_iam_policy_document.event_forwarder_assume[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "event_forwarder_assume" {
  count = var.governance_event_bus_arn != null ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "event_forwarder_policy" {
  count = var.governance_event_bus_arn != null ? 1 : 0

  name   = "allow-put-events-remote"
  role   = aws_iam_role.event_forwarder[0].id
  policy = data.aws_iam_policy_document.event_forwarder_policy[0].json
}

data "aws_iam_policy_document" "event_forwarder_policy" {
  count = var.governance_event_bus_arn != null ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [var.governance_event_bus_arn]
  }
}
