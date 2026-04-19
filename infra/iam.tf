# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — IAM execution role for Lambda
# File: infra/iam.tf
#
# Creates a scoped IAM role that grants Lambda exactly the permissions it needs:
#   - CloudWatch Logs (via AWSLambdaBasicExecutionRole managed policy)
#   - Amazon Bedrock InvokeModel (Nova Lite only)
#   - DynamoDB GetItem + PutItem (memory table only)
#   - Secrets Manager GetSecretValue (app secrets only)
#
# Principle of least privilege: no wildcard actions, no wildcard resources
# except Bedrock (the inference profile ARN format is non-standard).
# ─────────────────────────────────────────────────────────────────────────────

# ─── Trust policy — allows Lambda service to assume this role ─────────────────
resource "aws_iam_role" "lambda_exec" {
  name = "${local.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowLambdaAssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

# ─── Managed policy — CloudWatch Logs (CreateLogGroup, CreateLogStream, PutLogEvents) ──
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ─── Inline policy — Bedrock, DynamoDB, Secrets Manager ──────────────────────
resource "aws_iam_role_policy" "lambda_custom" {
  name = "${local.name}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Bedrock — InvokeModel for Nova Lite (inference profile uses wildcard resource
      # because cross-region profile ARNs are not standard foundation-model ARNs)
      {
        Sid      = "AllowBedrockInvoke"
        Effect   = "Allow"
        Action   = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
        # TODO (production): scope to specific model ARN once inference profile ARNs
        # are stable, e.g. arn:aws:bedrock:us-east-2::foundation-model/amazon.nova-lite-v1:0
      },

      # DynamoDB — read and write conversation history (scoped to the memory table only)
      {
        Sid    = "AllowDynamoDBMemory"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
        ]
        Resource = aws_dynamodb_table.memory.arn
      },

      # Secrets Manager — read app configuration (scoped to the app secret only)
      {
        Sid      = "AllowSecretsManagerRead"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.app_secrets.arn
      },
    ]
  })
}