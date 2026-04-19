# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — Terraform outputs
# File: infra/outputs.tf
#
# These values are printed after `terraform apply` and are referenced by:
#   - The GitHub Actions workflow in Part 4 (cloudfront_domain, api_gateway_url)
#   - The Next.js build (set NEXT_PUBLIC_API_URL = api_gateway_url before npm run build)
#   - The submission document (Checkpoint 3)
# ─────────────────────────────────────────────────────────────────────────────

output "cloudfront_domain" {
  description = "CloudFront distribution domain. Set as NEXT_PUBLIC_API_URL prefix and update Clerk allowed origins."
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "api_gateway_url" {
  description = "API Gateway invoke URL. Set NEXT_PUBLIC_API_URL to this value before npm run build."
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}"
}

output "s3_bucket_name" {
  description = "S3 bucket name. Run: aws s3 sync ./out s3://<this-value>/ --delete"
  value       = aws_s3_bucket.frontend.bucket
}

output "lambda_function_name" {
  description = "Lambda function name. Use for manual updates and GitHub Actions deploy step."
  value       = aws_lambda_function.api.function_name
}

output "dynamodb_table_name" {
  description = "DynamoDB memory table name. Passed to Lambda via DYNAMODB_TABLE env var."
  value       = aws_dynamodb_table.memory.name
}

output "secrets_manager_name" {
  description = "Secrets Manager secret name. Passed to Lambda via SECRETS_NAME env var."
  value       = aws_secretsmanager_secret.app_secrets.name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID. Used for cache invalidation in CI/CD."
  value       = aws_cloudfront_distribution.frontend.id
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC. Add as AWS_ROLE_ARN variable in GitHub repo Settings → Secrets and variables → Actions → Variables."
  value       = aws_iam_role.github_actions.arn
}