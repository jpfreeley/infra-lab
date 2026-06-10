"""RDS Auto-Stop Lambda.

Triggered by EventBridge when an RDS cluster starts.
Checks SSM parameter to determine if auto-stop is enabled.
If enabled, immediately stops the cluster.

This prevents the 7-day auto-restart from accumulating Aurora costs
when clusters are intended to remain stopped.
"""

import json
import logging

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")
rds = boto3.client("rds")

SSM_PARAMETER = "/infra-lab/rds-auto-stop/enabled"


def handler(event, context):
    """Handle RDS cluster start event."""
    logger.info("Event received: %s", json.dumps(event))

    # Extract cluster identifier from the event
    detail = event.get("detail", {})
    source_identifier = detail.get("SourceIdentifier", "")
    event_message = detail.get("Message", "")

    # Only act on cluster start events
    if "started" not in event_message.lower():
        logger.info("Not a start event, skipping: %s", event_message)
        return {"action": "skipped", "reason": "not a start event"}

    # Check SSM parameter
    try:
        response = ssm.get_parameter(Name=SSM_PARAMETER)
        enabled = response["Parameter"]["Value"].lower() == "true"
    except ssm.exceptions.ParameterNotFound:
        logger.warning("SSM parameter %s not found, defaulting to enabled", SSM_PARAMETER)
        enabled = True
    except Exception as e:
        logger.error("Error reading SSM parameter: %s", str(e))
        enabled = True  # Fail-safe: stop the cluster

    if not enabled:
        logger.info("Auto-stop is DISABLED via SSM parameter. Cluster will remain running.")
        return {"action": "skipped", "reason": "disabled via SSM", "cluster": source_identifier}

    # Stop the cluster
    logger.info("Auto-stop ENABLED. Stopping cluster: %s", source_identifier)
    try:
        rds.stop_db_cluster(DBClusterIdentifier=source_identifier)
        logger.info("Successfully initiated stop for cluster: %s", source_identifier)
        return {"action": "stopped", "cluster": source_identifier}
    except rds.exceptions.InvalidDBClusterStateFault:
        logger.warning("Cluster %s is not in a stoppable state", source_identifier)
        return {"action": "skipped", "reason": "not stoppable", "cluster": source_identifier}
    except Exception as e:
        logger.error("Error stopping cluster %s: %s", source_identifier, str(e))
        raise
