# -----------------------------------------------------------------------------
# Dashboard API Lambda Module - Main Configuration
# -----------------------------------------------------------------------------
# Creates the Lambda function that handles Dashboard API requests
# for compliance queries and exception management.
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "dashboard_api" {
  function_name = "${var.name_prefix}-dashboard-api"
  description   = "Dashboard API for compliance data and exception management"
  role          = aws_iam_role.dashboard_api.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.dashboard_api.output_path
  source_code_hash = data.archive_file.dashboard_api.output_base64sha256

  environment {
    variables = {
      COMPLIANCE_TABLE = var.compliance_table_name
      EXCEPTIONS_TABLE = var.exceptions_table_name
      LOG_LEVEL        = var.log_level
    }
  }

  tags = var.tags
}

data "archive_file" "dashboard_api" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/dist/dashboard_api.zip"
}

# =============================================================================
# IAM Role for Lambda
# =============================================================================

resource "aws_iam_role" "dashboard_api" {
  name               = "${var.name_prefix}-dashboard-api-role"
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

# Basic Lambda execution
resource "aws_iam_role_policy_attachment" "dashboard_api_basic" {
  role       = aws_iam_role.dashboard_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# DynamoDB access for compliance and exceptions tables
resource "aws_iam_role_policy" "dashboard_api_dynamodb" {
  name   = "${var.name_prefix}-dashboard-api-dynamodb"
  role   = aws_iam_role.dashboard_api.id
  policy = data.aws_iam_policy_document.dynamodb_access.json
}

data "aws_iam_policy_document" "dynamodb_access" {
  # Compliance table - read only
  statement {
    sid    = "ComplianceTableRead"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      var.compliance_table_arn,
      "${var.compliance_table_arn}/index/*"
    ]
  }

  # Exceptions table - full access for CRUD
  statement {
    sid    = "ExceptionsTableAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      var.exceptions_table_arn,
      "${var.exceptions_table_arn}/index/*"
    ]
  }
}
