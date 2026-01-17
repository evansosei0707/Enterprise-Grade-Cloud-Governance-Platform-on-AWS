# -----------------------------------------------------------------------------
# Remediation Engine Lambda Module - Main Configuration
# -----------------------------------------------------------------------------
# Creates the Lambda function that performs auto-remediation actions
# in member accounts by assuming the cross-account role.
# -----------------------------------------------------------------------------

# =============================================================================
# Lambda Function
# =============================================================================

resource "aws_lambda_function" "remediation_engine" {
  function_name = "${var.name_prefix}-remediation-engine"
  description   = "Performs auto-remediation actions in member accounts"
  role          = aws_iam_role.remediation_engine.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300  # Remediation might take longer
  memory_size   = 256

  filename         = data.archive_file.remediation_engine.output_path
  source_code_hash = data.archive_file.remediation_engine.output_base64sha256

  environment {
    variables = {
      REMEDIATION_ROLE_NAME   = var.remediation_role_name
      EXTERNAL_ID             = var.external_id
      LOG_LEVEL               = var.log_level
      ACCOUNT_ENVIRONMENT_MAP = jsonencode(var.account_environment_map)
      PROD_ACCOUNT_ID         = var.prod_account_id
      NOTIFICATION_LAMBDA     = var.notification_lambda_arn
    }
  }

  tags = var.tags
}

# =============================================================================
# Lambda Source Code Archive
# =============================================================================

data "archive_file" "remediation_engine" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/dist/remediation_engine.zip"
}

# =============================================================================
# IAM Role for Lambda
# =============================================================================

resource "aws_iam_role" "remediation_engine" {
  name               = "${var.name_prefix}-remediation-engine-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = var.tags
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

# =============================================================================
# IAM Policies
# =============================================================================

# Basic Lambda execution
resource "aws_iam_role_policy_attachment" "remediation_engine_basic" {
  role       = aws_iam_role.remediation_engine.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permission to assume cross-account remediation roles
resource "aws_iam_role_policy" "assume_cross_account_role" {
  name   = "${var.name_prefix}-assume-remediation-role"
  role   = aws_iam_role.remediation_engine.id
  policy = data.aws_iam_policy_document.assume_cross_account_role.json
}

data "aws_iam_policy_document" "assume_cross_account_role" {
  statement {
    sid    = "AssumeCrossAccountRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    # Restrict to the specific remediation role name in any account
    resources = ["arn:aws:iam::*:role/${var.remediation_role_name}"]
  }
}

# Permission to invoke notification Lambda for production safety fallback
resource "aws_iam_role_policy" "invoke_notification_lambda" {
  count = var.notification_lambda_arn != "" ? 1 : 0

  name   = "${var.name_prefix}-invoke-notification"
  role   = aws_iam_role.remediation_engine.id
  policy = data.aws_iam_policy_document.invoke_notification_lambda[0].json
}

data "aws_iam_policy_document" "invoke_notification_lambda" {
  count = var.notification_lambda_arn != "" ? 1 : 0

  statement {
    sid    = "InvokeNotificationLambda"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [var.notification_lambda_arn]
  }
}

