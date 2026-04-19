# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — Input variables
# File: infra/variables.tf
#
# Sensitive values are stored in terraform.tfvars (gitignored).
# Non-sensitive defaults are defined here.
# ─────────────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-2"
}

variable "clerk_jwks_url" {
  description = <<-EOT
    Clerk JWKS URL used by the Lambda backend to verify JWT signatures.
    Find it in Clerk Dashboard → Configure → API Keys → Advanced → JWKS URL.
    Format: https://<instance>.clerk.accounts.dev/.well-known/jwks.json
  EOT
  type      = string
  sensitive = true
}

variable "lambda_zip_path" {
  description = <<-EOT
    Path to the pre-built Lambda deployment ZIP, relative to the infra/ directory.
    Build it with:
      pip install ... --target ../package
      Copy-Item ../server.py,../lambda_handler.py,../dynamo_memory.py,../secrets.py ../package/
      Compress-Archive -Path ../package/* -DestinationPath ../codeguard.zip -Force
  EOT
  type    = string
  default = "../codeguard.zip"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds. Bedrock Nova Lite typically responds in 5-10s."
  type        = number
  default     = 30
}

variable "github_repo" {
  description = <<-EOT
    GitHub repository in owner/repo format.
    Used to scope the OIDC trust policy so only your repo's main branch can
    assume the GitHub Actions IAM role.
    Example: karangill17/codeguard
    Update this after pushing your project to GitHub, then re-run terraform apply.
  EOT
  type    = string
  default = "Karan-1708/Code-Guard"
}