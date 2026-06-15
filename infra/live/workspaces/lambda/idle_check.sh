#!/bin/bash
# Idle auto-stop script — runs every 15 minutes via cron
# Stops the instance if no DCV or code-server connections for IDLE_THRESHOLD minutes
#
# Installed by user_data at: /usr/local/bin/idle-check.sh
# Cron: */15 * * * * /usr/local/bin/idle-check.sh

IDLE_THRESHOLD_MINUTES=30  # Stop after 30 minutes of no connections
STATE_FILE="/var/run/last-dcv-activity"
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

# Check if any DCV session has active connections
CONNECTIONS=$(dcv list-sessions -j 2>/dev/null | grep -o '"num-of-connections" : [0-9]*' | awk -F: '{sum += $2} END {print sum+0}')

# Check if any code-server connections (port 8080)
CODE_SERVER_CONNECTIONS=$(ss -tn state established '( dport = :8080 or sport = :8080 )' 2>/dev/null | grep -c ESTAB || echo 0)

if [ "$CONNECTIONS" -gt 0 ] || [ "$CODE_SERVER_CONNECTIONS" -gt 0 ]; then
    # Someone is connected via DCV or code-server — update activity timestamp
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
    /usr/local/bin/aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
fi
