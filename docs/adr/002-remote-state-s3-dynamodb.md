# ADR-002: Remote State with S3 + DynamoDB

## Status

Accepted

## Context

Terraform state must be stored remotely for team collaboration, state locking,
and disaster recovery. Multiple backend options exist (S3, Terraform Cloud,
GCS, Consul).

## Decision

Use S3 for state storage with DynamoDB for state locking:

- S3 bucket with SSE-KMS encryption and versioning
- DynamoDB table for lock coordination
- Cross-region replication for DR (us-east-1 → us-west-2)

## Consequences

- State is encrypted at rest and in transit
- Concurrent applies are prevented by DynamoDB locking
- State history preserved via S3 versioning (rollback possible)
- Cost: ~$1/mo for KMS key + minimal S3/DDB usage
- Self-managed (vs Terraform Cloud) — more control, more responsibility
