# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — Lambda function
# File: infra/lambda.tf
#
# Deploys server.py (wrapped by lambda_handler.py via Mangum) as a Lambda
# function. The deployment ZIP must be pre-built before running terraform apply.
#
# Build commands (run from project root, PowerShell):
#   pip install pydantic pydantic-core `
#       --platform manylinux2014_x86_64 --python-version 3.12 `
#       --only-binary=:all: --target ./package
#   pip install fastapi mangum boto3 fastapi-clerk-auth uvicorn --target ./package
#   Copy-Item server.py,lambda_handler.py,dynamo_memory.py,secrets.py ./package/
#   Compress-Archive -Path ./package/* -DestinationPath codeguard.zip -Force
#
# source_code_hash ensures Terraform re-deploys the function whenever the ZIP
# content changes (even if the filename stays the same).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "api" {
  function_name = "${local.name}-api"
  description   = "CodeGuard FastAPI backend — Bedrock + DynamoDB + Secrets Manager"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_handler.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      # AWS_REGION is already set by the Lambda runtime — no need to set it here.
      # boto3 picks it up automatically via the standard AWS SDK env var chain.
      CLERK_JWKS_URL  = var.clerk_jwks_url
      DYNAMODB_TABLE  = aws_dynamodb_table.memory.name
      SECRETS_NAME    = aws_secretsmanager_secret.app_secrets.name
    }
  }

  tags = local.tags

  # Ensure the IAM role and its policies exist before the function is created.
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_custom,
  ]
}

# ─── Permission — allow API Gateway to invoke this Lambda ────────────────────
# Without this, API Gateway returns 403 on every request.
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"

  # Scope to this specific API Gateway only (not any API in the account).
  source_arn = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.http_api.id}/*/*"
}