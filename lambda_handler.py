"""
CodeGuard — Lambda entry point
================================
File: lambda_handler.py

Wraps the FastAPI app from server.py with the Mangum ASGI adapter so it can
run inside AWS Lambda. API Gateway sends a payload-format-version 2.0 event;
Mangum translates it into an ASGI request, passes it to FastAPI, and converts
the ASGI response back into the Lambda event response format.

lifespan="off" is required because Lambda does not support ASGI lifespan
events (startup/shutdown hooks). Without it, Mangum raises ASGILifespanError
before the handler processes any requests.

This file is intentionally minimal — all application logic lives in server.py.
"""

from mangum import Mangum
from server import app

handler = Mangum(app, lifespan="off")