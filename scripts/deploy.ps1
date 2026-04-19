# CodeGuard — Deploy script (Windows PowerShell)
# Usage:
#   .\deploy.ps1               — full deploy (Lambda + frontend)
#   .\deploy.ps1 -BuildOnly    — build Lambda zip only, no Terraform or S3 sync
#   .\deploy.ps1 -SkipLambda   — skip Lambda build/deploy, only sync frontend to S3

param(
    [switch]$BuildOnly,
    [switch]$SkipLambda
)

$ErrorActionPreference = "Stop"

# ── Helpers ────────────────────────────────────────────────────────────────────
function Info    { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Success { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Warn    { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Err     { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red; exit 1 }

function Require-Command {
    param($name)
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Err "'$name' is not installed or not in PATH."
    }
}

# ── Paths ──────────────────────────────────────────────────────────────────────
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root       = Split-Path -Parent $ScriptDir
$InfraDir   = Join-Path $Root "infra"
$PackageDir = Join-Path $Root "package"
$ZipPath    = Join-Path $Root "codeguard.zip"

# ── Prerequisite checks ────────────────────────────────────────────────────────
Info "Checking prerequisites..."
Require-Command python
Require-Command pip
Require-Command aws
if (-not $BuildOnly -and -not $SkipLambda) { Require-Command terraform }
if (-not $BuildOnly) { Require-Command node; Require-Command npm }
Success "All prerequisites found."

# ── Step 1: Build Lambda package ───────────────────────────────────────────────
if (-not $SkipLambda) {
    Info "Building Lambda package with Linux-compatible wheels..."

    if (Test-Path $PackageDir) { Remove-Item -Recurse -Force $PackageDir }
    New-Item -ItemType Directory -Path $PackageDir | Out-Null

    pip install `
        --platform manylinux2014_x86_64 `
        --target $PackageDir `
        --implementation cp `
        --python-version 3.12 `
        --only-binary=:all: `
        fastapi uvicorn boto3 mangum python-multipart fastapi-clerk-auth pydantic 2>&1 | Select-Object -Last 5

    # Verify Linux binaries
    $soFiles = Get-ChildItem "$PackageDir\pydantic_core\*.so" -ErrorAction SilentlyContinue
    if (-not $soFiles) {
        Err "Linux .so files not found in pydantic_core — build may have failed."
    }
    Success "Linux wheels installed."

    # Copy Python source files
    Copy-Item "$Root\lambda_handler.py" "$PackageDir\" -Force
    Copy-Item "$Root\server.py"         "$PackageDir\" -Force
    Copy-Item "$Root\dynamo_memory.py"  "$PackageDir\" -Force
    Copy-Item "$Root\secrets.py"        "$PackageDir\" -Force

    # Create zip using Python (zip command not available on Windows by default)
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    python -c @"
import zipfile, os

package_dir = r'$PackageDir'
zip_path    = r'$ZipPath'
skip_exts   = {'.pyc'}
skip_dirs   = {'__pycache__', 'bin'}

with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(package_dir):
        dirs[:] = [d for d in dirs if d not in skip_dirs and not d.endswith('.dist-info')]
        for f in files:
            if os.path.splitext(f)[1] in skip_exts:
                continue
            full = os.path.join(root, f)
            arc  = os.path.relpath(full, package_dir)
            zf.write(full, arc)

size_mb = os.path.getsize(zip_path) / 1024 / 1024
print(f'Built codeguard.zip — {size_mb:.1f} MB')
"@

    if ($BuildOnly) {
        Success "Build complete. Skipping Terraform and S3 sync."
        exit 0
    }
}

# ── Step 2: Terraform init + apply ────────────────────────────────────────────
Info "Running Terraform..."
Push-Location $InfraDir

if (-not (Test-Path "terraform.tfvars")) {
    Err "infra/terraform.tfvars not found. Copy terraform.tfvars.example and fill in your values."
}

terraform init -upgrade -input=false
Info "Terraform initialised."

$Workspace = terraform workspace show
Info "Terraform workspace: $Workspace"

terraform apply -auto-approve -input=false
Success "Terraform apply complete."

# ── Step 3: Read Terraform outputs ────────────────────────────────────────────
Info "Reading Terraform outputs..."
$CfDomain   = terraform output -raw cloudfront_domain
$ApiUrl     = terraform output -raw api_gateway_url
$S3Bucket   = terraform output -raw s3_bucket_name
$CfDistId   = terraform output -raw cloudfront_distribution_id
$LambdaName = terraform output -raw lambda_function_name

Write-Host ""
Write-Host "  CloudFront:   https://$CfDomain"
Write-Host "  API Gateway:  $ApiUrl"
Write-Host "  S3 Bucket:    $S3Bucket"
Write-Host "  Lambda:       $LambdaName"
Write-Host ""

Pop-Location

# ── Step 4: Build Next.js static export ───────────────────────────────────────
Info "Building Next.js static export..."
Set-Location $Root

if (-not (Test-Path ".env.local")) {
    Warn ".env.local not found. NEXT_PUBLIC_* variables will be empty."
    Warn "Create .env.local from the DEPLOYMENT.md guide before running this script."
}

# Override API URL with the live Terraform output
$env:NEXT_PUBLIC_API_URL = $ApiUrl

npm run build
Success "Next.js build complete. Output in .\out"

# ── Step 5: Sync frontend to S3 ───────────────────────────────────────────────
Info "Syncing frontend to S3 bucket: $S3Bucket..."
aws s3 sync .\out "s3://$S3Bucket/" --delete --quiet
Success "Frontend synced to S3."

# ── Step 6: Invalidate CloudFront cache ───────────────────────────────────────
Info "Invalidating CloudFront distribution: $CfDistId..."
$InvId = aws cloudfront create-invalidation `
    --distribution-id $CfDistId `
    --paths "/*" `
    --query "Invalidation.Id" `
    --output text
Success "CloudFront invalidation created: $InvId"

# ── Done ───────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║           Deployment Complete!               ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Live URL:  https://$CfDomain"
Write-Host "  API:       $ApiUrl/health"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "  1. Set CLERK_WEBHOOK_SECRET in .env.local"
Write-Host "  2. Add webhook endpoint in Clerk Dashboard:"
Write-Host "     https://$CfDomain/api/webhooks/clerk"
Write-Host "  3. Re-run this script if you update .env.local"
Write-Host ""
