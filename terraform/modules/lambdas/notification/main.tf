# -----------------------------------------------------------------------------
# Notification Lambda Module - Main Configuration
# -----------------------------------------------------------------------------
# Creates a Lambda function to format and send notifications via SNS and Slack.
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "notification" {
  function_name = "${var.name_prefix}-notification"
  description   = "Sends notifications for compliance events via SNS and Slack"
  role          = aws_iam_role.notification.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.notification.output_path
  source_code_hash = data.archive_file.notification.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN     = var.sns_topic_arn
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      ENABLE_SLACK      = var.enable_slack ? "true" : "false"
    }
  }

  tags = var.tags
}

data "archive_file" "notification" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/dist/notification.zip"
}

resource "aws_iam_role" "notification" {
  name               = "${var.name_prefix}-notification-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "notification_basic" {
  role       = aws_iam_role.notification.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "sns_publish" {
  name   = "${var.name_prefix}-sns-publish"
  role   = aws_iam_role.notification.id
  policy = data.aws_iam_policy_document.sns_publish.json
}

data "aws_iam_policy_document" "sns_publish" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}
