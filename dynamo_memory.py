"""
CodeGuard — DynamoDB conversation memory helper
================================================
File: dynamo_memory.py

Stores and retrieves per-session conversation history so users can ask
follow-up questions about a previous security review without re-submitting
their code. Each item in the DynamoDB table has:

    session_id (String, partition key) — UUID generated on first request
    messages   (List)                  — [{role, content}, ...] dicts
    ttl        (Number)                — Unix timestamp; item auto-deleted after 30 days

The DynamoDB resource (boto3.resource) is initialised once at module import
and reused across Lambda invocations within the same execution environment
(warm starts). This avoids creating a new connection on every request.

Environment variables:
    DYNAMODB_TABLE — table name provisioned by Terraform (e.g. codeguard-dev-memory)
"""

import os
import time
import logging
from typing import List, Dict

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

# ─── Module-level client (reused across warm Lambda invocations) ───────────────
_dynamodb = None

def _get_table():
    """Lazy-initialise the DynamoDB Table resource and cache it."""
    global _dynamodb
    if _dynamodb is None:
        _dynamodb = boto3.resource("dynamodb").Table(
            os.getenv("DYNAMODB_TABLE", "codeguard-dev-memory")
        )
    return _dynamodb


# ─── TTL ──────────────────────────────────────────────────────────────────────
TTL_DAYS = 30


# ─── Public API ───────────────────────────────────────────────────────────────

def load_conversation(session_id: str) -> List[Dict]:
    """
    Load conversation history for a session.

    Returns a list of message dicts in Bedrock converse() format:
        [{"role": "user", "content": [{"text": "..."}]}, ...]

    Returns an empty list if the session does not exist or on any error.
    Errors are logged but not re-raised — a missing history is not fatal;
    the review proceeds as a fresh conversation.
    """
    try:
        response = _get_table().get_item(Key={"session_id": session_id})
        return response.get("Item", {}).get("messages", [])
    except ClientError as e:
        logger.warning("DynamoDB load_conversation failed for %s: %s", session_id, e)
        return []


def save_conversation(session_id: str, messages: List[Dict]) -> None:
    """
    Persist updated conversation history with a 30-day TTL.

    Overwrites any existing item for this session_id. Errors are logged
    but not re-raised — a failed save means the next request starts fresh
    but does not break the current response.
    """
    ttl = int(time.time()) + (TTL_DAYS * 24 * 60 * 60)
    try:
        _get_table().put_item(Item={
            "session_id": session_id,
            "messages":   messages,
            "ttl":        ttl,
        })
    except ClientError as e:
        logger.warning("DynamoDB save_conversation failed for %s: %s", session_id, e)