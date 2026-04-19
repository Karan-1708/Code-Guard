# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — API Gateway HTTP API (v2)
# File: infra/api_gateway.tf
#
# Provisions a single HTTP API with:
#   - One Lambda integration (AWS_PROXY, payload-format-version 2.0)
#   - One catch-all route: ANY /{proxy+}
#   - One auto-deploy stage: prod
#   - CORS pre-flight (OPTIONS) handled by FastAPI's CORSMiddleware, not by
#     API Gateway, since we need dynamic CORS_ORIGINS from Secrets Manager.
# ─────────────────────────────────────────────────────────────────────────────

# ─── HTTP API ─────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
  description   = "CodeGuard HTTP API — routes all traffic to Lambda"

  tags = local.tags
}

# ─── Lambda integration ───────────────────────────────────────────────────────
# AWS_PROXY: API Gateway passes the full request to Lambda and returns its
# response verbatim. payload_format_version "2.0" is the format Mangum expects.
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

# ─── Catch-all route ──────────────────────────────────────────────────────────
# ANY /{proxy+} forwards every method and path to the Lambda integration.
# FastAPI's router handles the actual path dispatch internally.
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ─── Prod stage with auto-deploy ──────────────────────────────────────────────
# auto_deploy = true means every Lambda update is immediately live without
# requiring a manual stage re-deployment.
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "prod"
  auto_deploy = true

  tags = local.tags
}