# -----------------------------------------------------------------------------
# API Gateway Module - Main Configuration
# -----------------------------------------------------------------------------
# Creates REST API with custom domain, ACM certificate, and Route 53 DNS.
# Integrates with Dashboard API Lambda function.
# -----------------------------------------------------------------------------

# =============================================================================
# ACM Certificate for Custom Domain
# =============================================================================

resource "aws_acm_certificate" "api" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-api-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.hosted_zone_id
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# =============================================================================
# REST API
# =============================================================================

resource "aws_api_gateway_rest_api" "governance" {
  name        = "${var.name_prefix}-api"
  description = "Cloud Governance Platform API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

# =============================================================================
# API Resources and Methods
# =============================================================================

# /compliance
resource "aws_api_gateway_resource" "compliance" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_rest_api.governance.root_resource_id
  path_part   = "compliance"
}

# /compliance/summary
resource "aws_api_gateway_resource" "compliance_summary" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_resource.compliance.id
  path_part   = "summary"
}

resource "aws_api_gateway_method" "compliance_summary_get" {
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  resource_id   = aws_api_gateway_resource.compliance_summary.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "compliance_summary_get" {
  rest_api_id             = aws_api_gateway_rest_api.governance.id
  resource_id             = aws_api_gateway_resource.compliance_summary.id
  http_method             = aws_api_gateway_method.compliance_summary_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# /compliance/accounts/{account_id}
resource "aws_api_gateway_resource" "compliance_accounts" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_resource.compliance.id
  path_part   = "accounts"
}

resource "aws_api_gateway_resource" "compliance_accounts_id" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_resource.compliance_accounts.id
  path_part   = "{account_id}"
}

resource "aws_api_gateway_method" "compliance_accounts_get" {
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  resource_id   = aws_api_gateway_resource.compliance_accounts_id.id
  http_method   = "GET"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.path.account_id" = true
  }
}

resource "aws_api_gateway_integration" "compliance_accounts_get" {
  rest_api_id             = aws_api_gateway_rest_api.governance.id
  resource_id             = aws_api_gateway_resource.compliance_accounts_id.id
  http_method             = aws_api_gateway_method.compliance_accounts_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# /compliance/rules/{rule_name}
resource "aws_api_gateway_resource" "compliance_rules" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_resource.compliance.id
  path_part   = "rules"
}

resource "aws_api_gateway_resource" "compliance_rules_name" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_resource.compliance_rules.id
  path_part   = "{rule_name}"
}

resource "aws_api_gateway_method" "compliance_rules_get" {
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  resource_id   = aws_api_gateway_resource.compliance_rules_name.id
  http_method   = "GET"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.path.rule_name" = true
  }
}

resource "aws_api_gateway_integration" "compliance_rules_get" {
  rest_api_id             = aws_api_gateway_rest_api.governance.id
  resource_id             = aws_api_gateway_resource.compliance_rules_name.id
  http_method             = aws_api_gateway_method.compliance_rules_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# =============================================================================
# Exception Endpoints
# =============================================================================

# /exceptions
resource "aws_api_gateway_resource" "exceptions" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_rest_api.governance.root_resource_id
  path_part   = "exceptions"
}

# GET /exceptions
resource "aws_api_gateway_method" "exceptions_get" {
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  resource_id   = aws_api_gateway_resource.exceptions.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "exceptions_get" {
  rest_api_id             = aws_api_gateway_rest_api.governance.id
  resource_id             = aws_api_gateway_resource.exceptions.id
  http_method             = aws_api_gateway_method.exceptions_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# POST /exceptions
resource "aws_api_gateway_method" "exceptions_post" {
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  resource_id   = aws_api_gateway_resource.exceptions.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "exceptions_post" {
  rest_api_id             = aws_api_gateway_rest_api.governance.id
  resource_id             = aws_api_gateway_resource.exceptions.id
  http_method             = aws_api_gateway_method.exceptions_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# /exceptions/{exception_id}
resource "aws_api_gateway_resource" "exceptions_id" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_resource.exceptions.id
  path_part   = "{exception_id}"
}

# DELETE /exceptions/{exception_id}
resource "aws_api_gateway_method" "exceptions_delete" {
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  resource_id   = aws_api_gateway_resource.exceptions_id.id
  http_method   = "DELETE"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.path.exception_id" = true
  }
}

resource "aws_api_gateway_integration" "exceptions_delete" {
  rest_api_id             = aws_api_gateway_rest_api.governance.id
  resource_id             = aws_api_gateway_resource.exceptions_id.id
  http_method             = aws_api_gateway_method.exceptions_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# /exceptions/{exception_id}/approve
resource "aws_api_gateway_resource" "exceptions_approve" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_resource.exceptions_id.id
  path_part   = "approve"
}

resource "aws_api_gateway_method" "exceptions_approve" {
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  resource_id   = aws_api_gateway_resource.exceptions_approve.id
  http_method   = "PUT"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.path.exception_id" = true
  }
}

resource "aws_api_gateway_integration" "exceptions_approve" {
  rest_api_id             = aws_api_gateway_rest_api.governance.id
  resource_id             = aws_api_gateway_resource.exceptions_approve.id
  http_method             = aws_api_gateway_method.exceptions_approve.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# /exceptions/{exception_id}/reject
resource "aws_api_gateway_resource" "exceptions_reject" {
  rest_api_id = aws_api_gateway_rest_api.governance.id
  parent_id   = aws_api_gateway_resource.exceptions_id.id
  path_part   = "reject"
}

resource "aws_api_gateway_method" "exceptions_reject" {
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  resource_id   = aws_api_gateway_resource.exceptions_reject.id
  http_method   = "PUT"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.path.exception_id" = true
  }
}

resource "aws_api_gateway_integration" "exceptions_reject" {
  rest_api_id             = aws_api_gateway_rest_api.governance.id
  resource_id             = aws_api_gateway_resource.exceptions_reject.id
  http_method             = aws_api_gateway_method.exceptions_reject.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# =============================================================================
# API Deployment
# =============================================================================

resource "aws_api_gateway_deployment" "governance" {
  rest_api_id = aws_api_gateway_rest_api.governance.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.compliance.id,
      aws_api_gateway_resource.exceptions.id,
      aws_api_gateway_method.compliance_summary_get.id,
      aws_api_gateway_method.exceptions_get.id,
      aws_api_gateway_method.exceptions_post.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.compliance_summary_get,
    aws_api_gateway_integration.compliance_accounts_get,
    aws_api_gateway_integration.compliance_rules_get,
    aws_api_gateway_integration.exceptions_get,
    aws_api_gateway_integration.exceptions_post,
    aws_api_gateway_integration.exceptions_delete,
    aws_api_gateway_integration.exceptions_approve,
    aws_api_gateway_integration.exceptions_reject,
  ]
}

resource "aws_api_gateway_stage" "governance" {
  deployment_id = aws_api_gateway_deployment.governance.id
  rest_api_id   = aws_api_gateway_rest_api.governance.id
  stage_name    = var.stage_name

  tags = var.tags
}

# =============================================================================
# Custom Domain
# =============================================================================

resource "aws_api_gateway_domain_name" "governance" {
  domain_name              = var.domain_name
  regional_certificate_arn = aws_acm_certificate_validation.api.certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

resource "aws_api_gateway_base_path_mapping" "governance" {
  api_id      = aws_api_gateway_rest_api.governance.id
  stage_name  = aws_api_gateway_stage.governance.stage_name
  domain_name = aws_api_gateway_domain_name.governance.domain_name
}

# Route 53 record for custom domain
resource "aws_route53_record" "api" {
  name    = var.domain_name
  type    = "A"
  zone_id = var.hosted_zone_id

  alias {
    name                   = aws_api_gateway_domain_name.governance.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.governance.regional_zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# Lambda Permission for API Gateway
# =============================================================================

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.governance.execution_arn}/*/*"
}
