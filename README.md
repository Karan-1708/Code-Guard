# CodeGuard — AI-Powered Security Code Review

> Paste your code. Get an instant, severity-graded security review — complete with a corrected version and a plain-language briefing tailored to your experience level.

**Live app:** https://dgk2fbvlux214.cloudfront.net  
**Course:** AIE1018 — AI Deployment and MLOps | Cambrian College — Winter 2026  
**Student:** Karan Gill

---

## What it does

CodeGuard analyses submitted code and returns a structured three-section security review:

1. **Security Vulnerability Report** — every finding severity-graded (Critical / High / Medium / Low) with CWE identifiers and exact line references
2. **Corrected Code** — the full fixed version with every change annotated `# SECURITY FIX:`
3. **Developer Briefing** — plain-language explanation of real attack scenarios, calibrated to your experience level (Junior / Mid / Senior)

Supports 10 languages: Python, JavaScript, TypeScript, Java, C, C++, Rust, Go, PHP, Ruby.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 14 (Pages Router, TypeScript, Tailwind CSS) |
| Auth | Clerk (JWT, subscription gating via `<Protect>`) |
| Backend | FastAPI (Python 3.12) + Mangum |
| AI Model | AWS Bedrock — Amazon Nova Lite (`us.amazon.nova-lite-v1:0`) |
| Memory | AWS DynamoDB (conversation history, 30-day TTL) |
| Secrets | AWS Secrets Manager (CORS origins) |
| Compute | AWS Lambda (Python 3.12, x86_64, 30s timeout) |
| API | AWS API Gateway HTTP API (v2, payload format 2.0) |
| Hosting | AWS S3 (static export) + AWS CloudFront (HTTPS, edge cache) |
| IaC | Terraform (workspace-based dev/prod isolation) |
| CI/CD | GitHub Actions (AWS OIDC — no long-lived keys) |

---

## Project Structure

```
codeguard/
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD — Lambda + S3 + CloudFront deploy on push to main
├── api/
│   └── index.py                # Part 1: FastAPI backend for Vercel (OpenAI SSE)
├── infra/
│   ├── main.tf                 # Provider, locals, workspace config
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # Deployment outputs (URLs, ARNs)
│   ├── iam.tf                  # Lambda execution role (least-privilege)
│   ├── lambda.tf               # Lambda function + API Gateway permission
│   ├── api_gateway.tf          # HTTP API, Lambda integration, prod stage
│   ├── s3.tf                   # S3 bucket, public policy, website hosting
│   ├── cloudfront.tf           # CloudFront distribution, custom error responses
│   ├── dynamodb.tf             # Conversation memory table with TTL
│   ├── secrets.tf              # Secrets Manager (CORS origins)
│   ├── github_oidc.tf          # OIDC provider + GitHub Actions IAM role
│   └── terraform.tfvars.example
├── pages/
│   ├── index.tsx               # Landing page (hero, features, pricing)
│   ├── product.tsx             # Product page (code review form + output)
│   ├── _app.tsx                # ClerkProvider wrapper
│   ├── sign-in/[[...index]].tsx
│   └── sign-up/[[...index]].tsx
├── styles/
│   └── globals.css
├── dynamo_memory.py            # DynamoDB load/save conversation history
├── secrets.py                  # Secrets Manager CORS origins helper
├── server.py                   # Part 2/3: FastAPI backend for Lambda (Bedrock)
├── lambda_handler.py           # Mangum ASGI adapter
├── middleware.ts               # Clerk route protection
├── next.config.ts              # Static export config
├── tailwind.config.js
└── requirements.txt
```

---

## Local Development

### Prerequisites
- Node.js 20+
- Python 3.12+
- A [Clerk](https://clerk.com) account (free dev instance)

### 1. Clone and install

```bash
git clone https://github.com/Karan-1708/Code-Guard.git
cd Code-Guard
npm install
```

### 2. Set up environment variables

Create `.env.local` in the project root:

```env
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SECRET_KEY=sk_test_...
NEXT_PUBLIC_API_URL=http://localhost:8000
```

### 3. Run the frontend

```bash
npm run dev
# → http://localhost:3000
```

### 4. Run the backend (Part 1 — OpenAI)

```bash
pip install fastapi uvicorn openai fastapi-clerk-auth
export OPENAI_API_KEY=sk-...
export CLERK_JWKS_URL=https://your-instance.clerk.accounts.dev/.well-known/jwks.json
export CORS_ORIGINS=http://localhost:3000
uvicorn api.index:app --reload --port 8000
```

### 5. Run the backend (Parts 2–3 — Bedrock, local simulation)

```bash
pip install fastapi uvicorn boto3 mangum fastapi-clerk-auth
export CLERK_JWKS_URL=https://your-instance.clerk.accounts.dev/.well-known/jwks.json
export CORS_ORIGINS=http://localhost:3000
export DYNAMODB_TABLE=codeguard-dev-memory
# AWS credentials must be configured (aws configure or env vars)
uvicorn server:app --reload --port 8000
```

---

## Deployment

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://aws.amazon.com/cli/) configured (`aws configure`)
- AWS account with Bedrock Nova Lite access enabled

### 1. Build the Lambda package

```powershell
pip install pydantic pydantic-core `
    --platform manylinux2014_x86_64 --python-version 3.12 `
    --only-binary=:all: --target ./package
pip install fastapi mangum boto3 fastapi-clerk-auth uvicorn --target ./package
Copy-Item server.py,lambda_handler.py,dynamo_memory.py,secrets.py ./package/
Compress-Archive -Path ./package/* -DestinationPath codeguard.zip -Force
```

### 2. Provision infrastructure

```powershell
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set clerk_jwks_url and github_repo
terraform init
terraform workspace new dev
terraform apply -var-file=terraform.tfvars
```

### 3. Deploy frontend

```powershell
# Set NEXT_PUBLIC_API_URL from terraform output api_gateway_url
npm run build
aws s3 sync ./out s3://$(terraform -chdir=infra output -raw s3_bucket_name)/ --delete
aws cloudfront create-invalidation \
    --distribution-id $(terraform -chdir=infra output -raw cloudfront_distribution_id) \
    --paths "/*"
```

### 4. CI/CD (after first manual deploy)

Every push to `main` automatically runs the GitHub Actions pipeline. Required GitHub Actions variables and secrets — see `.github/workflows/deploy.yml` header for the full list.

---

## Architecture

```
User Browser
    │ HTTPS
    ▼
CloudFront ──► S3 (Next.js static export)
    │
    │ fetch POST /api (Clerk JWT)
    ▼
API Gateway (HTTP API)
    │ AWS_PROXY
    ▼
Lambda (Mangum + FastAPI)
    ├──► Clerk JWKS (JWT verification)
    ├──► Secrets Manager (CORS origins, cold start only)
    ├──► DynamoDB (load conversation history)
    ├──► Bedrock Nova Lite (converse())
    └──► DynamoDB (save updated history)
    │
    ▼
JSON response → CloudFront → Browser (ReactMarkdown renders output)
```

---

## Security Design

- **No AI API keys** — Bedrock access via Lambda IAM role (STS temporary credentials)
- **JWT verification** — every `/api` request validated against Clerk JWKS before reaching Bedrock
- **Subscription gate** — `<Protect plan="paid_subscription">` on frontend + JWT plan claim check on backend
- **Least-privilege IAM** — Lambda role allows only `InvokeModel`, `GetItem`/`PutItem` on its own table, `GetSecretValue` on its own secret
- **No long-lived CI keys** — GitHub Actions uses OIDC; deploy role limited to `UpdateFunctionCode`, S3 sync, CloudFront invalidation
- **Input validation** — Pydantic `InputRecord` with `Literal` types, `min_length`, `max_length`, and GitHub URL regex

---

## License

Built for AIE1018 Final Project — Cambrian College, Winter 2026.