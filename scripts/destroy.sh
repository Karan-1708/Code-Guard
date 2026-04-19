#!/usr/bin/env bash
# CodeGuard — Destroy script (Linux / macOS)
# Tears down all AWS infrastructure created by Terraform.
# WARNING: This permanently deletes all resources.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$ROOT/infra"

# ── Prerequisites ──────────────────────────────────────────────────────────────
command -v terraform &>/dev/null || error "'terraform' is not installed."
command -v aws &>/dev/null       || error "'aws' is not installed."

# ── Confirmation ───────────────────────────────────────────────────────────────
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  WARNING: This will permanently destroy all AWS resources.  ║${NC}"
echo -e "${RED}║  S3 bucket, Lambda, DynamoDB, CloudFront, API Gateway,      ║${NC}"
echo -e "${RED}║  IAM roles, and Secrets Manager will all be deleted.        ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

cd "$INFRA_DIR"

WORKSPACE=$(terraform workspace show 2>/dev/null || echo "default")
warn "Current Terraform workspace: $WORKSPACE"
echo ""
read -rp "Type 'yes' to confirm destruction of all resources: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  info "Destruction cancelled."
  exit 0
fi

# ── Empty S3 bucket before destroy (Terraform cannot delete non-empty buckets) ─
info "Reading Terraform state to find S3 bucket..."
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")

if [ -n "$S3_BUCKET" ]; then
  info "Emptying S3 bucket: $S3_BUCKET..."
  aws s3 rm "s3://$S3_BUCKET" --recursive --quiet && success "Bucket emptied." || \
    warn "Could not empty bucket — it may already be empty or not exist."
fi

# ── Terraform destroy ──────────────────────────────────────────────────────────
info "Running terraform destroy..."
terraform destroy -auto-approve -input=false

echo ""
success "All AWS resources have been destroyed."
echo ""
echo "  To redeploy, run:  ./deploy.sh"
echo ""
