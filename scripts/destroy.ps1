# CodeGuard - Destroy script (Windows PowerShell)
# Tears down all AWS infrastructure created by Terraform.
# WARNING: This permanently deletes all resources.

$ErrorActionPreference = "Stop"

function Info    { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Success { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Warn    { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Err     { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root      = Split-Path -Parent $ScriptDir
$InfraDir  = Join-Path $Root "infra"

# ── Prerequisites ──────────────────────────────────────────────────────────────
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { Err "'terraform' is not installed." }
if (-not (Get-Command aws      -ErrorAction SilentlyContinue)) { Err "'aws' is not installed." }

# ── Confirmation ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║   WARNING: This will permanently destroy all AWS resources.  ║" -ForegroundColor Red
Write-Host "║     S3 bucket, Lambda, DynamoDB, CloudFront, API Gateway,    ║" -ForegroundColor Red
Write-Host "║      IAM roles, and Secrets Manager will all be deleted.     ║" -ForegroundColor Red
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

Push-Location $InfraDir

$Workspace = terraform workspace show 2>$null
if (-not $Workspace) { $Workspace = "default" }
Warn "Current Terraform workspace: $Workspace"
Write-Host ""

$Confirm = Read-Host "Type 'yes' to confirm destruction of all resources"

if ($Confirm -ne "yes") {
    Info "Destruction cancelled."
    Pop-Location
    exit 0
}

# ── Empty S3 bucket before destroy (Terraform cannot delete non-empty buckets) ─
Info "Reading Terraform state to find S3 bucket..."
try {
    $S3Bucket = terraform output -raw s3_bucket_name 2>$null
} catch {
    $S3Bucket = ""
}

if ($S3Bucket) {
    Info "Emptying S3 bucket: $S3Bucket..."
    try {
        aws s3 rm "s3://$S3Bucket" --recursive --quiet
        Success "Bucket emptied."
    } catch {
        Warn "Could not empty bucket - it may already be empty or not exist."
    }
}

# ── Terraform destroy ──────────────────────────────────────────────────────────
Info "Running terraform destroy..."
terraform destroy -auto-approve -input=false

Pop-Location

Write-Host ""
Success "All AWS resources have been destroyed."
Write-Host ""
Write-Host "  To redeploy, run:  .\deploy.ps1"
Write-Host ""
