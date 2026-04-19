# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — GitHub Actions OIDC authentication
# File: infra/github_oidc.tf
#
# Allows GitHub Actions to authenticate with AWS using short-lived OIDC tokens
# instead of long-lived IAM access keys stored as GitHub secrets.
#
# How it works:
#   1. GitHub Actions requests a JWT from GitHub's OIDC provider
#   2. The workflow calls aws-actions/configure-aws-credentials with that token
#   3. AWS STS validates the token against the OIDC provider registered here
#   4. If the repo and branch match the trust policy, STS issues temporary creds
#   5. The workflow uses those credentials for Lambda, S3, and CloudFront calls
#
# No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY is ever stored in GitHub.
#
# After running terraform apply, update your GitHub repo:
#   Settings → Secrets and variables → Actions → Variables
#   Add: AWS_ROLE_ARN = <github_actions_role_arn from terraform output>
# ─────────────────────────────────────────────────────────────────────────────

# ─── GitHub OIDC Identity Provider ───────────────────────────────────────────
# Registers GitHub's OIDC token endpoint with AWS IAM so STS can validate
# tokens issued by GitHub Actions. Only needs to exist once per AWS account.
# The count = 0/1 pattern avoids errors if the provider already exists.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # The audience that GitHub includes in the JWT. Must match exactly.
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC certificate thumbprints.
  # AWS uses these to verify the token signature from GitHub's JWKS endpoint.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# ─── GitHub Actions IAM role ──────────────────────────────────────────────────
# This role is assumed by GitHub Actions during every workflow run.
# The trust policy restricts it to pushes from the main branch of your repo only.
resource "aws_iam_role" "github_actions" {
  name        = "${local.name}-github-actions"
  description = "Assumed by GitHub Actions via OIDC for CI/CD deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowGitHubActionsOIDC"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Restricts to pushes from the main branch of your specific repo.
        # Format: repo:<owner>/<repo>:ref:refs/heads/<branch>
        # Update var.github_repo in terraform.tfvars after pushing to GitHub.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = local.tags
}

# ─── Deployment policy — scoped to deploy-only operations ────────────────────
# CI can update code but cannot create or destroy infrastructure.
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "${local.name}-github-actions-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Lambda — update function code only (not config, not delete)
      {
        Sid      = "UpdateLambdaCode"
        Effect   = "Allow"
        Action   = "lambda:UpdateFunctionCode"
        Resource = aws_lambda_function.api.arn
      },

      # S3 — sync the Next.js build output (put, delete, list)
      {
        Sid    = "SyncFrontendBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.frontend.arn,
          "${aws_s3_bucket.frontend.arn}/*",
        ]
      },

      # CloudFront — invalidate the cache after every deploy
      {
        Sid      = "InvalidateCloudFrontCache"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.frontend.id}"
      },
    ]
  })
}