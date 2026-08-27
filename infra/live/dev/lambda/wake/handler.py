"""MemPalace Wake Lambda.

Lets MagNet Legal developers bring the shared mempalace stack (both
instances — the ALB/WAF/listener are shared infrastructure, see
docs/adr/034-shared-mempalace-server.md) back up themselves, without ever
needing GitHub or AWS access to infra-lab. Deliberately does not
reimplement any of mempalace-toggle.yml's up logic — it just triggers
that same, already-tested workflow via GitHub's REST API, the same way a
human clicking "Run workflow" would.

Auth is a bearer token in the Authorization header, checked against a
value stored in Secrets Manager (WAKE_TOKEN_SECRET_ARN) — a separate
credential from mempalace's own MEMPALACE_MCP_HTTP_TOKEN, distributed to
MagNet Legal developers directly. It grants only "permission to ask the
stack to wake up," nothing about mempalace data access itself.

The GitHub credential this function uses (a fine-grained PAT, scope
actions:write on jpfreeley/infra-lab only, stored in Secrets Manager at
GITHUB_PAT_SECRET_ARN) never reaches the caller — it's fetched
server-side, used for the one dispatch call, and never returned or
logged.
"""

import hmac
import json
import logging
import os
import urllib.error
import urllib.request

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

secretsmanager = boto3.client("secretsmanager")

GITHUB_REPO = os.environ.get("GITHUB_REPO", "jpfreeley/infra-lab")
WORKFLOW_FILE = os.environ.get("WORKFLOW_FILE", "mempalace-toggle.yml")
WAKE_TOKEN_SECRET_ARN = os.environ["WAKE_TOKEN_SECRET_ARN"]
GITHUB_PAT_SECRET_ARN = os.environ["GITHUB_PAT_SECRET_ARN"]


def _get_secret(secret_arn: str) -> str:
    response = secretsmanager.get_secret_value(SecretId=secret_arn)
    return response["SecretString"].strip()


def _extract_bearer_token(headers: dict) -> str:
    # Function URL headers are lowercased; check both cases defensively.
    auth_header = headers.get("authorization") or headers.get("Authorization") or ""
    if not auth_header.lower().startswith("bearer "):
        return ""
    return auth_header[len("Bearer "):].strip()


def _trigger_workflow_dispatch() -> tuple[int, str]:
    pat = _get_secret(GITHUB_PAT_SECRET_ARN)
    url = f"https://api.github.com/repos/{GITHUB_REPO}/actions/workflows/{WORKFLOW_FILE}/dispatches"
    payload = json.dumps({"ref": "main", "inputs": {"action": "up"}}).encode("utf-8")

    request = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {pat}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "mempalace-wake-lambda",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            # GitHub returns 204 No Content on a successful dispatch.
            return response.status, ""
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        logger.error("GitHub dispatch failed: %s %s", e.code, body)
        return e.code, body


def handler(event, context):
    headers = event.get("headers") or {}
    provided_token = _extract_bearer_token(headers)

    if not provided_token:
        return {"statusCode": 401, "body": json.dumps({"error": "missing bearer token"})}

    expected_token = _get_secret(WAKE_TOKEN_SECRET_ARN)

    if not hmac.compare_digest(provided_token, expected_token):
        logger.warning("Wake request with an invalid token, rejected.")
        return {"statusCode": 401, "body": json.dumps({"error": "invalid token"})}

    status, body = _trigger_workflow_dispatch()

    if status == 204:
        logger.info("Wake dispatch succeeded — mempalace-toggle.yml (up) triggered.")
        return {
            "statusCode": 202,
            "body": json.dumps({"status": "requested", "note": "stack is spinning up, usually a few minutes"}),
        }

    return {
        "statusCode": 502,
        "body": json.dumps({"error": "GitHub dispatch failed", "github_status": status, "github_body": body}),
    }
