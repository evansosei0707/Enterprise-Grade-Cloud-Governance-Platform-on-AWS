# -----------------------------------------------------------------------------
# Policy Engine Lambda Module - Main Configuration
# -----------------------------------------------------------------------------
# Creates the Lambda function that processes AWS Config compliance events,
# classifies severity, and routes to remediation or notification.
# -----------------------------------------------------------------------------

# =============================================================================
# Lambda Function
# =============================================================================

resource "aws_lambda_function" "policy_engine" {
  function_name = "${var.name_prefix}-policy-engine"
  description   = "Processes Config compliance events and classifies policy violations"
  role          = aws_iam_role.policy_engine.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.policy_engine.output_path
  source_code_hash = data.archive_file.policy_engine.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE      = var.dynamodb_table_name
      EXCEPTIONS_TABLE    = var.exceptions_table_name
      REMEDIATION_LAMBDA  = var.remediation_lambda_arn
      NOTIFICATION_LAMBDA = var.notification_lambda_arn
      ENVIRONMENT         = var.environment
      LOG_LEVEL           = var.log_level
    }
  }

  # VPC configuration (optional)
  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tags = var.tags
}

# =============================================================================
# Lambda Source Code Archive
# =============================================================================

data "archive_file" "policy_engine" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/dist/policy_engine.zip"
}

# =============================================================================
# IAM Role for Lambda
# =============================================================================

resource "aws_iam_role" "policy_engine" {
  name               = "${var.name_prefix}-policy-engine-role"
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
resource "aws_iam_role_policy_attachment" "policy_engine_basic" {
  role       = aws_iam_role.policy_engine.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# DynamoDB access
resource "aws_iam_role_policy" "policy_engine_dynamodb" {
  name   = "${var.name_prefix}-policy-engine-dynamodb"
  role   = aws_iam_role.policy_engine.id
  policy = data.aws_iam_policy_document.dynamodb_access.json
}

data "aws_iam_policy_document" "dynamodb_access" {
  statement {
    sid    = "DynamoDBAccess"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem"
    ]
    resources = [var.dynamodb_table_arn]
  }

  # Read access to exceptions table for whitelist checking
  dynamic "statement" {
    for_each = var.exceptions_table_arn != "" ? [1] : []
    content {
      sid    = "ExceptionsTableRead"
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:Query"
      ]
      resources = [
        var.exceptions_table_arn,
        "${var.exceptions_table_arn}/index/*"
      ]
    }
  }
}

# Lambda invocation for downstream functions
resource "aws_iam_role_policy" "policy_engine_invoke" {
  name   = "${var.name_prefix}-policy-engine-invoke"
  role   = aws_iam_role.policy_engine.id
  policy = data.aws_iam_policy_document.lambda_invoke.json
}

data "aws_iam_policy_document" "lambda_invoke" {
  statement {
    sid    = "LambdaInvoke"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = compact([
      var.remediation_lambda_arn,
      var.notification_lambda_arn
    ])
  }
}
