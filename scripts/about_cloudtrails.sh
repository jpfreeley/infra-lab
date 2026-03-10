#!/bin/bash

# Disable the pager for all AWS CLI commands in this script
export AWS_PAGER=""

# 1. Check if profile parameter is provided
if [ -z "$1" ]; then
  echo "Usage: ./check_trails.sh <aws-profile>"
  echo "Example: ./check_trails.sh infra-lab"
  exit 1
fi

PROFILE=$1
# Default region since it's missing from your credentials-only profile
REGION="us-east-1"

echo "----------------------------------------------------------------"
echo "Checking CloudTrails for Profile: $PROFILE (Account: 551452024305)"
echo "----------------------------------------------------------------"

# 2. Verify authentication first
if ! aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" > /dev/null 2>&1; then
    echo "Error: Cannot authenticate with profile '$PROFILE' in region '$REGION'."
    echo "Please ensure '$PROFILE' exists in ~/.aws/credentials."
    exit 1
fi

# 3. Get the list of all trails (including the hidden Control Tower shadow trails)
TRAILS=$(aws cloudtrail describe-trails --include-shadow-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[].Name' --output text)

if [ -z "$TRAILS" ] || [ "$TRAILS" == "None" ]; then
    echo "No CloudTrails found."
    exit 0
fi

# 4. Loop through each trail and extract the specific info needed for consolidation
for TRAIL in $TRAILS; do
    echo ">>> TRAIL NAME: $TRAIL"

    # Get Status (Is it active?)
    echo "Status:"
    aws cloudtrail get-trail-status --name "$TRAIL" --profile "$PROFILE" --region "$REGION" \
        --query '{Logging:IsLogging,LastDelivery:LatestDeliveryTime}' --output json

    # Get Configuration (Where is the data going?)
    echo "Configuration:"
    aws cloudtrail describe-trails --trail-name-list "$TRAIL" --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].{S3Bucket:S3BucketName,S3Prefix:S3KeyPrefix,MultiRegion:IsMultiRegionTrail,OrgTrail:IsOrganizationTrail,LogGroup:CloudWatchLogsLogGroupArn}' --output json
    echo "----------------------------------------------------------------"
done
