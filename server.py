"""
CodeGuard — FastAPI backend for Lambda deployment (Part 3)
==========================================================
File: server.py
Runtime: AWS Lambda (Python 3.12, x86_64) via Mangum adapter

Changes from Part 2 → Part 3:
  - CORS origins now read from AWS Secrets Manager via secrets.py
    (instead of a plain CORS_ORIGINS environment variable)
  - DynamoDB conversation memory integrated via dynamo_memory.py
    — each session accumulates user + assistant turns
    — users can ask follow-up questions without re-submitting code
  - session_id returned in every response so the frontend can send it
    back on the next request

Environment variables required (set by Terraform in lambda.tf):
  CLERK_JWKS_URL  — Clerk JWKS endpoint for JWT signature verification
  DYNAMODB_TABLE  — DynamoDB table name (e.g. codeguard-dev-memory)
  SECRETS_NAME    — Secrets Manager secret name (e.g. codeguard-dev-secrets)

No API keys stored anywhere — Bedrock and DynamoDB access is granted via
the Lambda IAM execution role (codeguard-dev-lambda-role).
"""

import os
import logging
from typing import Optional, Literal
from uuid import uuid4

import boto3
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator
from fastapi_clerk_auth import ClerkConfig, ClerkHTTPBearer, HTTPAuthorizationCredentials

from dynamo_memory import load_conversation, save_conversation
from secrets import get_cors_origins

logger = logging.getLogger(__name__)

# ─── Bedrock client (module-level — reused across warm Lambda invocations) ────
bedrock  = boto3.client("bedrock-runtime")
MODEL_ID = "us.amazon.nova-lite-v1:0"

# ─── App initialisation ────────────────────────────────────────────────────────
app = FastAPI(title="CodeGuard API", version="3.0")

# ─── CORS — origins loaded from Secrets Manager at cold start ─────────────────
# get_cors_origins() caches the result after the first call, so warm Lambda
# invocations pay no Secrets Manager latency.
app.add_middleware(
    CORSMiddleware,
    allow_origins     = get_cors_origins(),
    allow_credentials = False,
    allow_methods     = ["GET", "POST", "OPTIONS"],
    allow_headers     = ["*"],
)

# ─── Clerk JWT authentication ─────────────────────────────────────────────────
clerk_config = ClerkConfig(jwks_url=os.getenv("CLERK_JWKS_URL", ""))
clerk_guard  = ClerkHTTPBearer(clerk_config)


# ─── Pydantic InputRecord model ────────────────────────────────────────────────
# Contract between frontend (product.tsx) and backend.
# Every snake_case key here must exactly match the JSON.stringify() call in
# product.tsx, or FastAPI returns 422 Unprocessable Entity.

class InputRecord(BaseModel):
    code_snippet: str = Field(
        ...,
        min_length=10,
        description="Raw source code to review. Minimum 10 characters.",
    )
    language: Literal[
        "Python", "JavaScript", "TypeScript", "Java",
        "C", "C++", "Rust", "Go", "PHP", "Ruby"
    ] = Field(..., description="Programming language of the submitted code.")

    context: str = Field(
        ...,
        max_length=500,
        description="Brief description of what the code does and how it is used.",
    )
    experience_level: Literal["Junior", "Mid", "Senior"] = Field(
        ...,
        description="Controls tone of the Developer Briefing section.",
    )
    severity_threshold: Literal["Critical", "High", "Medium", "Low"] = Field(
        ...,
        description="Minimum severity level to include in the Vulnerability Report.",
    )
    github_url: Optional[str] = Field(
        None,
        description="Optional GitHub URL to the file or PR being reviewed.",
    )
    session_id: Optional[str] = Field(
        None,
        description="Session identifier for conversation continuity. "
                    "Omit on first request; include on follow-up questions.",
    )

    @field_validator("github_url")
    @classmethod
    def validate_github_url(cls, v: Optional[str]) -> Optional[str]:
        if v and v.strip():
            if not v.strip().startswith("https://github.com/"):
                raise ValueError(
                    "github_url must start with https://github.com/ — "
                    "e.g. https://github.com/username/repo/blob/main/file.py"
                )
            return v.strip()
        return None


# ─── System prompt ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """
You are CodeGuard, a senior security-focused code review assistant with deep expertise in
secure software development, the OWASP Top 10, CWE/CVE classification, and common
vulnerability patterns across Python, JavaScript, TypeScript, Java, C, C++, Rust, Go,
PHP, Ruby, and other mainstream programming languages. Your role is to analyse submitted
code with the precision of a professional penetration tester and the clarity of a senior
engineering mentor.

You always produce exactly three sections in the following order, using the exact Markdown
headings shown below. Do not add, rename, or reorder these sections under any circumstances.

## Security Vulnerability Report
List every identified security issue in a structured format. For each issue include: a
severity label (Critical, High, Medium, or Low), the CWE identifier where applicable
(e.g., CWE-89 SQL Injection, CWE-79 Cross-Site Scripting), the specific line number or
code pattern where the issue appears, and a concise technical description of the
vulnerability and why it is dangerous in a real attack context. Order findings from highest
to lowest severity. If no issues exist at a given severity level, omit that level entirely.
If no vulnerabilities are found at all, state this explicitly rather than inventing issues.

## Corrected Code
Provide the complete corrected version of the submitted code. Every security-relevant change
must be annotated with an inline comment beginning with `# SECURITY FIX:` (or
`// SECURITY FIX:` for C-style languages) that explains exactly what was changed and why.
Do not silently rewrite code — every change must be visible, labelled, and justified inline.
Preserve the original logic and functionality of the code in all parts that do not require
a security change.

## Developer Briefing
Write a plain-language explanation intended for the developer who submitted this code.
Explain what an attacker could realistically do by exploiting each identified vulnerability —
be specific and scenario-based, not generic. Provide a prioritised action list starting
with the most critical item. Calibrate the technical depth of this section to the
developer's stated experience level: use analogies and accessible language for Junior
developers; assume more domain knowledge and skip basic explanations for Mid and Senior
levels. Be constructive — the goal of this section is to build security awareness and
teach good habits, not to criticise.

Constraint rules you must always follow:
- Do not invent vulnerabilities that are not present in the submitted code.
- Do not modify the logic, functionality, or intended behaviour of the code beyond what is
  necessary to address identified security issues.
- If the submitted code is in a language you cannot analyse reliably, say so explicitly
  rather than producing a speculative or potentially incorrect review.
- Base your review only on the code provided. Do not make assumptions about unseen parts
  of the system or external dependencies that are not visible in the snippet.
- If the developer has set a severity threshold (e.g., High and above only), omit findings
  below that threshold from the Security Vulnerability Report, but note in the Developer
  Briefing that lower-severity items were filtered and recommend the developer re-run
  without a threshold filter for a complete picture.
""".strip()


# ─── User prompt builder ───────────────────────────────────────────────────────
def user_prompt_for(record: InputRecord) -> str:
    """
    Build the user-turn message from an InputRecord.
    Every field is labelled explicitly so the model can unambiguously
    associate each value with its meaning (see Q1.2 in the submission doc).
    """
    lines = [
        f"Language: {record.language}",
        f"Developer Experience Level: {record.experience_level}",
        f"Severity Threshold: {record.severity_threshold} "
        f"(report findings at this severity level and above only)",
        f"Code Context: {record.context}",
    ]
    if record.github_url:
        lines.append(f"GitHub Reference: {record.github_url}")

    lang_fence = record.language.lower().replace("+", "p").replace("#", "sharp")
    lines.append(f"\nCode to Review:\n```{lang_fence}\n{record.code_snippet}\n```")
    return "\n".join(lines)


# ─── Health endpoint ───────────────────────────────────────────────────────────
@app.get("/health")
def health_check():
    return {"status": "healthy", "version": "3.0"}


# ─── Main POST endpoint ────────────────────────────────────────────────────────
@app.post("/api")
def process(
    record: InputRecord,
    creds: HTTPAuthorizationCredentials = Depends(clerk_guard),
):
    """
    Accepts a CodeGuard InputRecord, verifies the Clerk JWT, loads conversation
    history from DynamoDB, calls Bedrock Nova Lite via converse(), appends the
    new turn to history, saves it back to DynamoDB, and returns a JSON response.

    Response body: { "response": "<structured Markdown>", "session_id": "<uuid>" }

    The frontend sets NEXT_PUBLIC_API_URL to the API Gateway invoke URL and
    uses a plain fetch() call — no SSE required for the non-streaming variant.
    """

    # ── Resolve session ID ─────────────────────────────────────────────────────
    # Use the session_id from the request if provided (follow-up question),
    # otherwise generate a new UUID (first request in a new session).
    session_id = record.session_id or str(uuid4())

    # ── Load conversation history ──────────────────────────────────────────────
    # Returns [] for a new session. Each item is a Bedrock message dict:
    # {"role": "user" | "assistant", "content": [{"text": "..."}]}
    history = load_conversation(session_id)

    # ── Append the new user message ────────────────────────────────────────────
    new_user_message = {
        "role":    "user",
        "content": [{"text": user_prompt_for(record)}],
    }
    messages = history + [new_user_message]

    # ── Call Bedrock Nova Lite ─────────────────────────────────────────────────
    response = bedrock.converse(
        modelId  = MODEL_ID,
        system   = [{"text": SYSTEM_PROMPT}],
        messages = messages,
    )
    assistant_text = response["output"]["message"]["content"][0]["text"]

    # ── Append the assistant response and persist ──────────────────────────────
    messages.append({
        "role":    "assistant",
        "content": [{"text": assistant_text}],
    })
    save_conversation(session_id, messages)

    return JSONResponse(content={
        "response":   assistant_text,
        "session_id": session_id,
    })