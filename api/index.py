"""
CodeGuard — FastAPI backend for Vercel deployment (Part 1)
==========================================================
File:    api/index.py
Runtime: Vercel Python serverless function

This file handles:
  - InputRecord Pydantic model (contract between frontend and backend)
  - System prompt and user prompt construction
  - Clerk JWT authentication via fastapi-clerk-auth
  - OpenAI GPT-4o-mini streaming response using Server-Sent Events (SSE)
  - /health endpoint for Lambda testing in Part 2

Environment variables required (set via `vercel env add`):
  OPENAI_API_KEY                  — OpenAI API key
  CLERK_JWKS_URL                  — Clerk JWKS URL for JWT verification
  NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY — (used by frontend, not this file)
  CLERK_SECRET_KEY                — (used by frontend/middleware, not this file)
  CORS_ORIGINS                    — comma-separated list of allowed origins
                                    e.g. https://your-app.vercel.app,http://localhost:3000
"""

import os
from typing import Optional, Literal

from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel, Field, field_validator
from fastapi_clerk_auth import ClerkConfig, ClerkHTTPBearer, HTTPAuthorizationCredentials
from openai import OpenAI

app = FastAPI(title="CodeGuard API", version="1.0")

cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

clerk_config = ClerkConfig(jwks_url=os.getenv("CLERK_JWKS_URL", ""))
clerk_guard  = ClerkHTTPBearer(clerk_config)


class InputRecord(BaseModel):
    code_snippet: str = Field(..., min_length=10)
    language: Literal["Python", "JavaScript", "TypeScript", "Java", "C", "C++", "Rust", "Go", "PHP", "Ruby"]
    context: str = Field(..., max_length=2000)
    experience_level: Literal["Junior", "Mid", "Senior"]
    severity_threshold: Literal["Critical", "High", "Medium", "Low"]
    github_url: Optional[str] = Field(None)
    session_id: Optional[str] = Field(None)

    @field_validator("github_url")
    @classmethod
    def validate_github_url(cls, v: Optional[str]) -> Optional[str]:
        if v and v.strip():
            if not v.strip().startswith("https://github.com/"):
                raise ValueError("github_url must start with https://github.com/")
            return v.strip()
        return None


system_prompt = """
You are CodeGuard, a senior security-focused code review assistant. Your role is to analyze code snippets for security vulnerabilities with extreme precision.

You MUST produce exactly three sections in the following order, using the exact Markdown
headings shown below:

## Security Vulnerability Report
List every identified security issue. For each, include:
- **Severity**: (Critical, High, Medium, or Low)
- **CWE**: The CWE identifier (e.g., CWE-89)
- **Location**: Specific line number or pattern
- **Description**: Technical explanation of the risk.
Insert a single Markdown horizontal rule (---) BETWEEN vulnerabilities. Do NOT add a horizontal rule before the first vulnerability or after the last vulnerability.
If no issues are found, state "No vulnerabilities identified."

## Corrected Code
Provide the complete corrected version of the code. 
**CRITICAL**: You must wrap the code in a Markdown code block with the appropriate language tag (e.g., ```python or ```javascript). 
Every security change must be annotated with an inline comment (e.g., # SECURITY FIX: or // SECURITY FIX:).

## Developer Briefing
Provide a plain-language summary followed by an action list. Use the following sub-headings:
### Summary of Risks
Explain what an attacker could realistically do.
### Prioritized Action List
List the steps the developer should take.
""".strip()


def user_prompt_for(record: InputRecord) -> str:
    lines = [
        f"Language: {record.language}",
        f"Developer Experience: {record.experience_level}",
        f"Severity Threshold: {record.severity_threshold}",
        f"Context: {record.context}",
    ]
    if record.github_url:
        lines.append(f"GitHub: {record.github_url}")
    lang_fence = record.language.lower().replace("+", "p").replace("#", "sharp")
    lines.append(f"\nCode to Review:\n```{lang_fence}\n{record.code_snippet}\n```")
    return "\n".join(lines)


@app.get("/health")
def health_check():
    return {"status": "healthy", "version": "1.0"}


@app.post("/api/py-review")
def process(
    record: InputRecord,
    creds: HTTPAuthorizationCredentials = Depends(clerk_guard),
):
    user_id = creds.decoded["sub"]
    client = OpenAI()
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user",   "content": user_prompt_for(record)},
    ]
    stream = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=messages,
        stream=True,
    )

    def event_stream():
        buffer = ""
        for chunk in stream:
            token = chunk.choices[0].delta.content
            if token is None:
                continue
            buffer += token
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                yield f"data: {line}\n\n"
        if buffer:
            yield f"data: {buffer}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
