"""Trigger mempalace-idle-teardown.yml on a reliable schedule.

GitHub's own `schedule:` cron trigger for that workflow is best-effort
with no SLA — observed gaps as large as ~4 hours during periods of
platform load (2026-08-27), which meaningfully undermines a workflow
whose whole point is catching an idle stack within roughly 90 minutes.
This Lambda, invoked directly by a real EventBridge Scheduler
rate(15 minutes) schedule (which does carry an SLA), calls the exact
same workflow via GitHub's REST API — the same way GitHub's own cron
trigger would. It doesn't reimplement any teardown logic, just triggers
the existing, already-tested workflow more reliably. Runs alongside the
existing `schedule:` cron trigger in the workflow file, not instead of
it — belt and suspenders, since GitHub's trigger still fires sometimes
too, just unreliably.

Invoked directly by EventBridge Scheduler via IAM (the schedule's own
target role, granted lambda:InvokeFunction on this function only) — no
Function URL, not publicly reachable, unlike the sibling wake Lambda in
this same directory which deliberately is public. Reuses the same
GitHub PAT already stored for that wake Lambda (actions:write on
jpfreeley/infra-lab only) rather than creating a second credential.
"""

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
WORKFLOW_FILE = os.environ.get("WORKFLOW_FILE", "mempalace-idle-teardown.yml")
GITHUB_PAT_SECRET_ARN = os.environ["GITHUB_PAT_SECRET_ARN"]


def _get_secret(secret_arn: str) -> str:
    response = secretsmanager.get_secret_value(SecretId=secret_arn)
    return response["SecretString"].strip()


def handler(event, context):
    pat = _get_secret(GITHUB_PAT_SECRET_ARN)
    url = f"https://api.github.com/repos/{GITHUB_REPO}/actions/workflows/{WORKFLOW_FILE}/dispatches"
    payload = json.dumps({"ref": "main"}).encode("utf-8")

    request = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {pat}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "mempalace-idle-teardown-trigger-lambda",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            # GitHub returns 204 No Content on a successful dispatch.
            logger.info("Idle-teardown dispatch succeeded: HTTP %s", response.status)
            return {"status": response.status}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        logger.error("GitHub dispatch failed: %s %s", e.code, body)
        # Re-raise so the invocation shows as a failure in CloudWatch/
        # Lambda metrics — a silently-swallowed failure here would
        # recreate exactly the "looks fine, isn't actually running"
        # problem this Lambda exists to fix.
        raise
