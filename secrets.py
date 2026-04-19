"""
CodeGuard — AWS Secrets Manager helper
=======================================
File: secrets.py

Reads runtime configuration from AWS Secrets Manager and caches it in memory
after the first call. On Lambda, the module is imported once per execution
environment — subsequent warm invocations hit the in-process cache and make
no network calls.

The secret stores a JSON object. Currently:
    { "CORS_ORIGINS": "https://d1234abcd.cloudfront.net" }

For local development, CORS_ORIGINS can be set as a plain environment variable
to bypass Secrets Manager entirely:
    CORS_ORIGINS=http://localhost:3000 uvicorn server:app --reload

Environment variables:
    SECRETS_NAME — Secrets Manager secret name (e.g. codeguard-dev-secrets)
    CORS_ORIGINS — Optional override; used for local dev without Secrets Manager
"""

import json
import logging
import os
from typing import List

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

# ─── In-process cache (keyed by secret name) ──────────────────────────────────
_cache: dict = {}


def _get_secret(secret_name: str) -> dict:
    """
    Fetch a secret from Secrets Manager and cache the result.

    Returns the parsed JSON as a dict. On error, returns an empty dict
    so callers can fall back to their own defaults without crashing.
    """
    if secret_name in _cache:
        return _cache[secret_name]

    try:
        client   = boto3.client("secretsmanager")
        response = client.get_secret_value(SecretId=secret_name)
        value    = json.loads(response["SecretString"])
        _cache[secret_name] = value
        logger.info("Loaded secret '%s' from Secrets Manager.", secret_name)
        return value
    except ClientError as e:
        logger.error("Failed to fetch secret '%s': %s", secret_name, e)
        return {}


def get_cors_origins() -> List[str]:
    """
    Return the list of allowed CORS origins.

    Resolution order:
      1. CORS_ORIGINS environment variable (local dev / manual override)
      2. CORS_ORIGINS key inside the Secrets Manager secret (production)
      3. Fallback: ["http://localhost:3000"]

    Returns a list of stripped origin strings.
    """
    # 1. Environment variable override (local dev)
    env_value = os.getenv("CORS_ORIGINS", "").strip()
    if env_value:
        return [o.strip() for o in env_value.split(",") if o.strip()]

    # 2. Secrets Manager
    secret_name = os.getenv("SECRETS_NAME", "codeguard-dev-secrets")
    secret      = _get_secret(secret_name)
    origins_str = secret.get("CORS_ORIGINS", "").strip()
    if origins_str:
        return [o.strip() for o in origins_str.split(",") if o.strip()]

    # 3. Fallback
    logger.warning("CORS_ORIGINS not found in env or Secrets Manager. Defaulting to localhost.")
    return ["http://localhost:3000"]