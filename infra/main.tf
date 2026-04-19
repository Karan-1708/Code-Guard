# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — Terraform root configuration
# File: infra/main.tf
#
# Declares the AWS provider, required Terraform version, and shared locals.
# All other resources live in their own *.tf files in this directory.
#
# Usage:
#   cd infra
#   terraform init
#   terraform workspace new dev      # first time only
#   terraform plan  -var-file=terraform.tfvars
#   terraform apply -var-file=terraform.tfvars
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment the block below in Part 4 to store state in S3 + DynamoDB locking.
  # backend "s3" {
  #   bucket         = "codeguard-tfstate"
  #   key            = "codeguard/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "codeguard-tfstate-lock"
  # }
}

# ─── AWS provider ─────────────────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region
}

# ─── Caller identity — used for Lambda permission ARNs ────────────────────────
data "aws_caller_identity" "current" {}

# ─── Shared locals ────────────────────────────────────────────────────────────
# terraform.workspace is "dev" by default, "prod" for Bonus A.
# All resource names include the workspace suffix so dev and prod can coexist
# in the same AWS account without collisions.
locals {
  app  = "codeguard"
  env  = terraform.workspace   # "dev" | "prod"
  name = "${local.app}-${local.env}"

  # Tags applied to every taggable resource.
  tags = {
    App       = "CodeGuard"
    Env       = local.env
    ManagedBy = "Terraform"
    Course    = "AIE1018"
  }
}