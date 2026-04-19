# CodeGuard — Complete Deployment Guide

This guide walks you through cloning the repository and deploying the full CodeGuard stack to AWS from scratch. By the end you will have a live CloudFront URL serving the Next.js frontend, an API Gateway + Lambda backend powered by Amazon Bedrock, a DynamoDB conversation memory table, and a GitHub Actions CI/CD pipeline for future deployments.

---

## Architecture Overview

```
User → CloudFront (CDN) → S3 (Next.js static export)
User → API Gateway (HTTP API v2) → Lambda (FastAPI + Mangum) → Bedrock (Nova Lite)
                                                              → DynamoDB (session memory)
                                                              → Secrets Manager (CORS config)
Clerk (Auth + Billing) → Webhook → Next.js API route → Clerk SDK (update user metadata)
```

---

## Prerequisites

Install all of the following before starting.

### 1. AWS CLI
- Download: https://aws.amazon.com/cli/
- Verify: `aws --version`
- Must be v2.x or later

### 2. Terraform
- Download: https://developer.hashicorp.com/terraform/downloads
- Verify: `terraform --version`
- Must be v1.5.0 or later

### 3. Node.js
- Download: https://nodejs.org/ (LTS version)
- Verify: `node --version` and `npm --version`
- Must be Node 20+

### 4. Python 3.12
- Download: https://www.python.org/downloads/
- Verify: `python --version` (must show 3.12.x)
- Must be exactly 3.12 to match the Lambda runtime

### 5. Git
- Download: https://git-scm.com/downloads
- Verify: `git --version`

### 6. AWS Account
- Create one at https://aws.amazon.com/ if you don't have one
- You need an IAM user or role with the following permissions:
  - AdministratorAccess (for initial Terraform setup)
  - Or a scoped policy covering: Lambda, S3, CloudFront, DynamoDB, IAM, API Gateway, Secrets Manager, CloudWatch

### 7. Clerk Account
- Sign up at https://clerk.com
- Create a new application (call it "CodeGuard")
- Go to **Billing** and set up two plans:
  - Plan 1 — Name: `Free`, Slug: `free_user`, Price: $0/month
  - Plan 2 — Name: `Paid Subscription`, Slug: `paid_subscription`, Price: $30/month
- **Slugs must match exactly** — the app checks `user.publicMetadata.plan === "paid_subscription"`

---

## Step 1 — Clone the Repository

```bash
git clone https://github.com/Karan-1708/Code-Guard.git codeguard
cd codeguard
```

---

## Step 2 — Configure AWS Credentials

```bash
aws configure
```

Enter when prompted:
- **AWS Access Key ID** — from IAM → Users → your user → Security credentials
- **AWS Secret Access Key** — same place (only shown once when created)
- **Default region name** — `us-east-2`
- **Default output format** — `json`

Verify it works:
```bash
aws sts get-caller-identity
```
You should see your account ID and user ARN.

---

## Step 3 — Install Node.js Dependencies

```bash
npm install
```

---

## Step 4 — Set Up Clerk Keys

1. Go to **Clerk Dashboard → API Keys**
2. Copy your **Publishable Key** (starts with `pk_test_...` for dev, `pk_live_...` for prod)
3. Copy your **Secret Key** (starts with `sk_test_...` or `sk_live_...`)
4. Go to **JWT Templates → Clerk** and copy the **JWKS URL**
   - It looks like: `https://your-app.clerk.accounts.dev/.well-known/jwks.json`
5. Go to **Webhooks → Add Endpoint** (you will fill in the URL after Terraform runs)
   - Subscribe to: `subscription.created`, `subscription.updated`
   - Copy the **Signing Secret** after creating it

---

## Step 5 — Create the Terraform Variables File

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `infra/terraform.tfvars` and fill in your values:

```hcl
aws_region      = "us-east-2"
clerk_jwks_url  = "https://your-app.clerk.accounts.dev/.well-known/jwks.json"
lambda_zip_path = "../codeguard.zip"
github_repo     = "Karan-1708/Code-Guard"
```

> **Note:** `lambda_zip_path` points to the zip you will build in Step 6. Leave it as `../codeguard.zip`.

---

## Step 6 — Build the Lambda Deployment Package

The Lambda runs on Linux. You must build dependencies with Linux-compatible binaries even if you are on Windows.

**On Windows — run in PowerShell:**
```powershell
cd scripts
.\deploy.ps1 -BuildOnly
```

**On Linux / macOS — run in terminal:**
```bash
cd scripts
chmod +x deploy.sh
./deploy.sh --build-only
```

This creates `codeguard.zip` in the project root directory. You should see output like:
```
Built codeguard.zip — 22.5 MB
```

---

## Step 7 — Run Terraform (Provision AWS Infrastructure)

```bash
cd infra
terraform init
terraform workspace new dev   # or 'prod' for production
terraform plan
terraform apply
```

Type `yes` when prompted to confirm.

Terraform will create:
- S3 bucket for the frontend
- Lambda function with your code
- API Gateway HTTP API
- CloudFront distribution
- DynamoDB table for conversation history
- Secrets Manager secret for CORS config
- IAM roles and policies
- GitHub Actions OIDC role

**This takes approximately 3–5 minutes.** CloudFront distributions take the longest.

At the end, Terraform prints outputs like:
```
cloudfront_domain     = "d1234abcd.cloudfront.net"
api_gateway_url       = "https://abc123.execute-api.us-east-2.amazonaws.com"
s3_bucket_name        = "codeguard-dev-frontend"
lambda_function_name  = "codeguard-dev-api"
dynamodb_table_name   = "codeguard-dev-memory"
```

**Save these values** — you need them in the next steps.

---

## Step 8 — Create the .env.local File

Back in the project root, create `.env.local`:

```env
# Clerk Authentication
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_your_key_here
CLERK_SECRET_KEY=sk_test_your_key_here
CLERK_JWKS_URL=https://your-app.clerk.accounts.dev/.well-known/jwks.json
CLERK_WEBHOOK_SECRET=whsec_your_webhook_secret_here

# Clerk URL config
NEXT_PUBLIC_CLERK_SIGN_IN_URL=/sign-in
NEXT_PUBLIC_CLERK_SIGN_UP_URL=/sign-up
NEXT_PUBLIC_CLERK_AFTER_SIGN_IN_URL=/product
NEXT_PUBLIC_CLERK_AFTER_SIGN_UP_URL=/product

# API — use the api_gateway_url from Terraform output
NEXT_PUBLIC_API_URL=https://abc123.execute-api.us-east-2.amazonaws.com
```

> Replace every value with your actual keys and the `api_gateway_url` from Step 7.

---

## Step 9 — Add Clerk API Keys to AWS Secrets Manager

Terraform created a secret in Secrets Manager for CORS config. You also need to manually add the Clerk secret key to Lambda's environment so the webhook works.

Go to **AWS Console → Lambda → your function → Configuration → Environment Variables** and verify these are set (Terraform sets `CLERK_JWKS_URL` automatically — the others you add manually):

| Key | Value |
|-----|-------|
| `CLERK_JWKS_URL` | Set by Terraform ✓ |
| `DYNAMODB_TABLE` | Set by Terraform ✓ |
| `SECRETS_NAME` | Set by Terraform ✓ |

The backend reads Clerk JWKS from `CLERK_JWKS_URL` for JWT verification. No secret key is needed on the Lambda side.

---

## Step 10 — Deploy the Frontend to S3

Run the full deploy script (builds Next.js and uploads to S3):

**On Windows:**
```powershell
cd scripts
.\deploy.ps1 -SkipLambda
```

**On Linux / macOS:**
```bash
cd scripts
./deploy.sh --skip-lambda
```

Or run everything (Lambda + frontend) in one shot:

**On Windows:**
```powershell
.\deploy.ps1
```

**On Linux / macOS:**
```bash
./deploy.sh
```

---

## Step 11 — Set Up the Clerk Webhook

Now that you have a live CloudFront URL:

1. Go to **Clerk Dashboard → Webhooks → Add Endpoint**
2. URL: `https://d1234abcd.cloudfront.net/api/webhooks/clerk`
   - Replace with your actual CloudFront domain from Step 7
3. Subscribe to: `subscription.created`, `subscription.updated`
4. Click **Create** and copy the **Signing Secret**
5. Add this to `.env.local`:
   ```env
   CLERK_WEBHOOK_SECRET=whsec_your_new_secret
   ```
6. Redeploy the frontend so it picks up the new env var:
   - **Windows:** `.\deploy.ps1 -SkipLambda`
   - **Linux/macOS:** `./deploy.sh --skip-lambda`

---

## Step 12 — Set Up GitHub Actions CI/CD (Optional)

If you want automatic deployments on every push to `main`:

1. Push your code to GitHub:
   ```bash
   git remote set-url origin https://github.com/Karan-1708/Code-Guard.git
   git push origin main
   ```

2. Go to your GitHub repo → **Settings → Secrets and variables → Actions**

3. Add these **Variables** (not secrets):

   | Name | Value |
   |------|-------|
   | `AWS_ROLE_ARN` | `github_actions_role_arn` from Terraform output |
   | `AWS_REGION` | `us-east-2` |
   | `LAMBDA_FUNCTION_NAME` | `lambda_function_name` from Terraform output |
   | `S3_BUCKET_NAME` | `s3_bucket_name` from Terraform output |
   | `CF_DISTRIBUTION_ID` | `cloudfront_distribution_id` from Terraform output |
   | `NEXT_PUBLIC_API_URL` | `api_gateway_url` from Terraform output |

4. Add these **Secrets**:

   | Name | Value |
   |------|-------|
   | `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Your Clerk publishable key |

5. The workflow triggers automatically on every push to `main`.

---

## Step 13 — Verify the Deployment

1. Open your CloudFront URL: `https://d1234abcd.cloudfront.net`
2. You should see the CodeGuard landing page
3. Sign up with a new account
4. Go to `/product` and paste some code — you should get a security review from Bedrock
5. Go to `/upgrade` — you should see the Clerk pricing table
6. Test a payment (use Clerk's test card: `4242 4242 4242 4242`, any future date, any CVC)
7. After payment, refresh `/product` — premium features should be unlocked

**Test the Lambda directly:**
```bash
aws lambda invoke \
  --function-name codeguard-dev-api \
  --region us-east-2 \
  --payload '{"version":"2.0","routeKey":"GET /health","rawPath":"/health","rawQueryString":"","headers":{"host":"localhost"},"requestContext":{"http":{"method":"GET","path":"/health","protocol":"HTTP/1.1","sourceIp":"127.0.0.1","userAgent":"test"},"requestId":"test"},"isBase64Encoded":false}' \
  response.json
cat response.json
```
Expected: `{"statusCode":200,"body":"{\"status\":\"healthy\",\"version\":\"3.0\"}"}`

---

## Tearing Down

To destroy all AWS resources (stop incurring charges):

**On Windows:**
```powershell
cd scripts
.\destroy.ps1
```

**On Linux / macOS:**
```bash
cd scripts
./destroy.sh
```

> **Warning:** This permanently deletes all resources including the S3 bucket, DynamoDB data, and Lambda function. Type `yes` to confirm.

---

## Environment Variables Reference

### `.env.local` (frontend — never commit this file)

| Variable | Where to find it |
|----------|-----------------|
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk Dashboard → API Keys |
| `CLERK_SECRET_KEY` | Clerk Dashboard → API Keys |
| `CLERK_JWKS_URL` | Clerk Dashboard → JWT Templates → Clerk |
| `CLERK_WEBHOOK_SECRET` | Clerk Dashboard → Webhooks → your endpoint |
| `NEXT_PUBLIC_CLERK_SIGN_IN_URL` | Set to `/sign-in` |
| `NEXT_PUBLIC_CLERK_SIGN_UP_URL` | Set to `/sign-up` |
| `NEXT_PUBLIC_CLERK_AFTER_SIGN_IN_URL` | Set to `/product` |
| `NEXT_PUBLIC_CLERK_AFTER_SIGN_UP_URL` | Set to `/product` |
| `NEXT_PUBLIC_API_URL` | `api_gateway_url` from Terraform output |

### `infra/terraform.tfvars` (Terraform — never commit this file)

| Variable | Description |
|----------|-------------|
| `aws_region` | AWS region (default: `us-east-2`) |
| `clerk_jwks_url` | Clerk JWKS URL for JWT verification |
| `lambda_zip_path` | Path to the built Lambda zip (default: `../codeguard.zip`) |
| `github_repo` | GitHub repo in `owner/name` format |

---

## Troubleshooting

### "No module named pydantic_core._pydantic_core"
The Lambda package was built on Windows. Re-run the deploy script — it always builds with Linux-compatible wheels using `--platform manylinux2014_x86_64`.

### "Failed to connect to the CodeGuard API"
`NEXT_PUBLIC_API_URL` is missing or set to `localhost`. Set it to the `api_gateway_url` from Terraform output and redeploy the frontend.

### Pricing table not showing plans
The plans in Clerk Dashboard must have slugs exactly matching `free_user` and `paid_subscription`. Check the slug in Clerk → Billing → Plans.

### Premium not activating after payment
Check the webhook endpoint in Clerk Dashboard — the URL must point to your live CloudFront domain, not localhost. Check the signing secret matches `CLERK_WEBHOOK_SECRET`. Check the Lambda/CloudWatch logs for the webhook handler.

### CloudFront returning old content
Run a cache invalidation:
```bash
aws cloudfront create-invalidation \
  --distribution-id YOUR_CF_DISTRIBUTION_ID \
  --paths "/*"
```

### Terraform state issues
If you get "resource already exists" errors, the state may be out of sync. Import the existing resource or run `terraform destroy` and start fresh.
