# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — Secrets Manager secret for runtime configuration
# File: infra/secrets.tf
#
# Stores CORS_ORIGINS so the Lambda backend can read it at cold-start without
# needing it as a plain-text environment variable.
#
# The secret value references the CloudFront domain name directly, which means
# Terraform will create the CloudFront distribution first, then create the secret
# version with the resulting domain. This is handled automatically via the
# implicit dependency on aws_cloudfront_distribution.frontend.domain_name.
#
# recovery_window_in_days = 0 allows immediate deletion (no 30-day recovery
# period). Suitable for dev; set to 30 for production.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${local.name}-secrets"
  description             = "CodeGuard runtime configuration — CORS origins."
  recovery_window_in_days = 0   # Set to 30 in production

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  # Reference the CloudFront domain directly. Terraform resolves this after
  # the CloudFront distribution is created (implicit dependency).
  secret_string = jsonencode({
    CORS_ORIGINS = "https://${aws_cloudfront_distribution.frontend.domain_name}"
  })
}