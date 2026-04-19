#!/usr/bin/env bash
# CodeGuard — Deploy script (Linux / macOS)
# Usage:
#   ./deploy.sh               — full deploy (Lambda + frontend)
#   ./deploy.sh --build-only  — build Lambda zip only, no Terraform or S3 sync
#   ./deploy.sh --skip-lambda — skip Lambda build/deploy, only sync frontend to S3

set -euo pipefail

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# ── Flags ──────────────────────────────────────────────────────────────────────
BUILD_ONLY=false
SKIP_LAMBDA=false
for arg in "$@"; do
  case $arg in
    --build-only)  BUILD_ONLY=true ;;
    --skip-lambda) SKIP_LAMBDA=true ;;
    *) error "Unknown argument: $arg" ;;
  esac
done

# ── Paths ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$ROOT/infra"
PACKAGE_DIR="$ROOT/package"
ZIP_PATH="$ROOT/codeguard.zip"

# ── Prerequisite checks ────────────────────────────────────────────────────────
check_cmd() { command -v "$1" &>/dev/null || error "'$1' is not installed or not in PATH."; }
info "Checking prerequisites..."
check_cmd python3
check_cmd pip
check_cmd aws
if [ "$BUILD_ONLY" = false ] && [ "$SKIP_LAMBDA" = false ]; then check_cmd terraform; fi
if [ "$BUILD_ONLY" = false ]; then check_cmd node; check_cmd npm; fi
success "All prerequisites found."

# ── Step 1: Build Lambda package ───────────────────────────────────────────────
if [ "$SKIP_LAMBDA" = false ]; then
  info "Building Lambda package with Linux-compatible wheels..."

  rm -rf "$PACKAGE_DIR"
  mkdir -p "$PACKAGE_DIR"

  pip install \
    --platform manylinux2014_x86_64 \
    --target "$PACKAGE_DIR" \
    --implementation cp \
    --python-version 3.12 \
    --only-binary=:all: \
    fastapi uvicorn boto3 mangum python-multipart fastapi-clerk-auth pydantic \
    2>&1 | tail -5

  # Verify Linux binaries
  if ! ls "$PACKAGE_DIR/pydantic_core/"*.so &>/dev/null; then
    error "Linux .so files not found in pydantic_core — build may have failed."
  fi
  success "Linux wheels installed."

  # Copy Python source files
  cp "$ROOT/lambda_handler.py"  "$PACKAGE_DIR/"
  cp "$ROOT/server.py"          "$PACKAGE_DIR/"
  cp "$ROOT/dynamo_memory.py"   "$PACKAGE_DIR/"
  cp "$ROOT/secrets.py"         "$PACKAGE_DIR/"

  # Create zip
  rm -f "$ZIP_PATH"
  cd "$PACKAGE_DIR"
  zip -r "$ZIP_PATH" . -x "*.pyc" -x "__pycache__/*" -x "*.dist-info/*" -x "bin/*" \
    > /dev/null
  cd "$ROOT"

  ZIP_MB=$(du -m "$ZIP_PATH" | cut -f1)
  success "Built codeguard.zip — ${ZIP_MB} MB"

  if [ "$BUILD_ONLY" = true ]; then
    success "Build complete. Skipping Terraform and S3 sync."
    exit 0
  fi
fi

# ── Step 2: Terraform init + apply ────────────────────────────────────────────
info "Running Terraform..."
cd "$INFRA_DIR"

if [ ! -f "terraform.tfvars" ]; then
  error "infra/terraform.tfvars not found. Copy terraform.tfvars.example and fill in your values."
fi

terraform init -upgrade -input=false
info "Terraform initialised."

WORKSPACE=$(terraform workspace show)
info "Terraform workspace: $WORKSPACE"

terraform apply -auto-approve -input=false
success "Terraform apply complete."

# ── Step 3: Read Terraform outputs ────────────────────────────────────────────
info "Reading Terraform outputs..."
CF_DOMAIN=$(terraform output -raw cloudfront_domain)
API_URL=$(terraform output -raw api_gateway_url)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
CF_DIST_ID=$(terraform output -raw cloudfront_distribution_id)
LAMBDA_NAME=$(terraform output -raw lambda_function_name)

echo ""
echo "  CloudFront:   https://$CF_DOMAIN"
echo "  API Gateway:  $API_URL"
echo "  S3 Bucket:    $S3_BUCKET"
echo "  Lambda:       $LAMBDA_NAME"
echo ""

cd "$ROOT"

# ── Step 4: Build Next.js static export ───────────────────────────────────────
info "Building Next.js static export..."

if [ ! -f ".env.local" ]; then
  warn ".env.local not found. NEXT_PUBLIC_* variables will be empty."
  warn "Create .env.local from the DEPLOYMENT.md guide before running this script."
fi

# Override API URL with the live Terraform output
export NEXT_PUBLIC_API_URL="$API_URL"

npm run build
success "Next.js build complete. Output in ./out"

# ── Step 5: Sync frontend to S3 ───────────────────────────────────────────────
info "Syncing frontend to S3 bucket: $S3_BUCKET..."
aws s3 sync ./out "s3://$S3_BUCKET/" --delete --quiet
success "Frontend synced to S3."

# ── Step 6: Invalidate CloudFront cache ───────────────────────────────────────
info "Invalidating CloudFront distribution: $CF_DIST_ID..."
aws cloudfront create-invalidation \
  --distribution-id "$CF_DIST_ID" \
  --paths "/*" \
  --query "Invalidation.Id" \
  --output text
success "CloudFront invalidation created."

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Deployment Complete!               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Live URL:  https://$CF_DOMAIN"
echo "  API:       $API_URL/health"
echo ""
echo "  Next steps:"
echo "  1. Set CLERK_WEBHOOK_SECRET in .env.local"
echo "  2. Add webhook endpoint in Clerk Dashboard:"
echo "     https://$CF_DOMAIN/api/webhooks/clerk"
echo "  3. Re-run this script if you update .env.local"
echo ""
