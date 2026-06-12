#!/bin/bash
# Idle auto-stop script — runs every 15 minutes via cron
# Stops the instance if no DCV connections for IDLE_THRESHOLD minutes
#
# Installed by user_data at: /usr/local/bin/idle-check.sh
# Cron: */15 * * * * /usr/local/bin/idle-check.sh

IDLE_THRESHOLD_MINUTES=30  # Stop after 30 minutes of no connections
STATE_FILE="/var/run/last-dcv-activity"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Check if any DCV session has active connections
CONNECTIONS=$(dcv list-sessions -j 2>/dev/null | grep -o '"num-of-connections" : [0-9]*' | awk -F: '{sum += $2} END {print sum+0}')

if [ "$CONNECTIONS" -gt 0 ]; then
    # Someone is connected — update activity timestamp
    date +%s > "$STATE_FILE"
    exit 0
fi

# No connections — check how long it's been idle
if [ ! -f "$STATE_FILE" ]; then
    # No state file = first boot, start tracking now
    date +%s > "$STATE_FILE"
    exit 0
fi

LAST_ACTIVITY=$(cat "$STATE_FILE")
NOW=$(date +%s)
IDLE_SECONDS=$((NOW - LAST_ACTIVITY))
IDLE_MINUTES=$((IDLE_SECONDS / 60))

if [ "$IDLE_MINUTES" -ge "$IDLE_THRESHOLD_MINUTES" ]; then
    logger -t idle-check "No DCV connections for ${IDLE_MINUTES} minutes. Stopping instance."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
fi
