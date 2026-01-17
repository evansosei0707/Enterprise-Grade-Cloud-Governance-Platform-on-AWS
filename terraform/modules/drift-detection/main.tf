# -----------------------------------------------------------------------------
# Drift Detection Module - Main Configuration
# -----------------------------------------------------------------------------
# Lambda function that compares Terraform state with actual AWS resources.
# Scheduled via EventBridge to run daily at 7pm UTC.
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "drift_detection" {
  function_name = "${var.name_prefix}-drift-detection"
  description   = "Detects drift between Terraform state and AWS resources"
  role          = aws_iam_role.drift_detection.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300 # 5 minutes for full scan
  memory_size   = 512

  filename         = data.archive_file.drift_detection.output_path
  source_code_hash = data.archive_file.drift_detection.output_base64sha256

  environment {
    variables = {
      TF_STATE_BUCKET     = var.tf_state_bucket
      TF_STATE_KEY        = var.tf_state_key
      NOTIFICATION_LAMBDA = var.notification_lambda_arn
      LOG_LEVEL           = var.log_level
    }
  }

  tags = var.tags
}

data "archive_file" "drift_detection" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/dist/drift_detection.zip"
}

# =============================================================================
# EventBridge Schedule
# =============================================================================

resource "aws_cloudwatch_event_rule" "drift_schedule" {
  name                = "${var.name_prefix}-drift-detection-schedule"
  description         = "Triggers drift detection daily at 7pm UTC"
  schedule_expression = var.schedule_expression

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "drift_lambda" {
  rule      = aws_cloudwatch_event_rule.drift_schedule.name
  target_id = "DriftDetectionLambda"
  arn       = aws_lambda_function.drift_detection.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drift_detection.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.drift_schedule.arn
}

# =============================================================================
# IAM Role
# =============================================================================

resource "aws_iam_role" "drift_detection" {
  name               = "${var.name_prefix}-drift-detection-role"
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

resource "aws_iam_role_policy_attachment" "drift_basic" {
  role       = aws_iam_role.drift_detection.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 access for Terraform state
resource "aws_iam_role_policy" "drift_s3" {
  name   = "${var.name_prefix}-drift-s3"
  role   = aws_iam_role.drift_detection.id
  policy = data.aws_iam_policy_document.s3_access.json
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    sid    = "ReadTerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.tf_state_bucket}",
      "arn:aws:s3:::${var.tf_state_bucket}/*"
    ]
  }
}

# AWS Config read access
resource "aws_iam_role_policy" "drift_config" {
  name   = "${var.name_prefix}-drift-config"
  role   = aws_iam_role.drift_detection.id
  policy = data.aws_iam_policy_document.config_access.json
}

data "aws_iam_policy_document" "config_access" {
  statement {
    sid    = "ReadConfigHistory"
    effect = "Allow"
    actions = [
      "config:GetResourceConfigHistory",
      "config:ListDiscoveredResources",
      "config:BatchGetResourceConfig"
    ]
    resources = ["*"]
  }
}

# Lambda invoke for notifications
resource "aws_iam_role_policy" "drift_lambda_invoke" {
  name   = "${var.name_prefix}-drift-lambda-invoke"
  role   = aws_iam_role.drift_detection.id
  policy = data.aws_iam_policy_document.lambda_invoke.json
}

data "aws_iam_policy_document" "lambda_invoke" {
  statement {
    sid    = "InvokeNotificationLambda"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [var.notification_lambda_arn]
  }
}
