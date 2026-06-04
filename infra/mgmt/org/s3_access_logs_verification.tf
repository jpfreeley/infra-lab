####
# S3 Access Logs Verification for Central Buckets - E03-S014
#
# This file documents the access logging posture of all central S3 buckets.
# No additional Terraform resources are needed — all active central buckets
# already have access logging enabled.
#
# MANAGEMENT ACCOUNT (551452024305):
# ┌─────────────────────────────────────────────────────┐
# │ terraform_state bucket                              │
# │   → logs to: log_bucket (state-logs)               │
# │     → logs to: log_bucket_logs                     │
# │       → logs to: log_bucket_logs_access_logs       │
# │         → self-logging (terminal)                  │
# └─────────────────────────────────────────────────────┘
# All configured in infra/mgmt/backend/main.tf with cross-region replication.
#
# LOG ARCHIVE ACCOUNT (172134854767):
# ┌─────────────────────────────────────────────────────────────────────┐
# │ aws-controltower-cloudtrail-logs-172134854767-frp-ikz               │
# │   → logs to: aws-controltower-cloudtrail-access-logs-*             │
# │                                                                     │
# │ aws-controltower-logs-172134854767-us-east-1                        │
# │   → logs to: aws-controltower-s3-access-logs-172134854767-us-east-1│
# │                                                                     │
# │ infra-lab-cloudtrail-logs-v2-172134854767 (EMPTY / LEGACY)          │
# │   → No logging. SCP p-rfhbth3m blocks PutBucketLogging.           │
# │   → Empty bucket, no active data. Candidate for cleanup.           │
# └─────────────────────────────────────────────────────────────────────┘
#
# CONCLUSION:
# - All active central buckets have access logging enabled.
# - Control Tower manages logging for CT-created buckets via guardrails.
# - The legacy infra-lab-cloudtrail-logs-v2 bucket is empty and protected
#   by CT SCP. It cannot be modified and is a cleanup candidate.
# - No additional Terraform resources required for this story.
#
# VERIFIED: 2026-06-03 by infra-lab AI Assistant.
####
