# Disaster Recovery Strategy

## RPO / RTO Targets

| Environment | RPO (Data Loss) | RTO (Recovery Time) | Strategy |
| --- | --- | --- | --- |
| Dev | 24 hours | 4 hours | Rebuild from IaC + daily backup |
| Staging | 1 hour | 1 hour | Aurora PITR + IaC redeploy |
| Prod (future) | 5 minutes | 15 minutes | Aurora Global DB + multi-AZ + blue/green |

## Current Capabilities (Dev)

### Compute (ECS)

- **Recovery method**: `terraform apply` recreates all services from code
- **RTO**: ~10 minutes (ECS task launch time)
- **RPO**: N/A (stateless — no data in compute tier)
- **Blast radius**: Single AZ failure has no impact (tasks spread across AZs)

### Database (Aurora)

- **Recovery method**: AWS Backup restore or Aurora PITR
- **RTO**: ~30 minutes (restore snapshot, update DNS/proxy)
- **RPO**: 24 hours (daily backup in dev; 5-minute PITR available from Aurora continuous backup)
- **PITR window**: 7 days (backup_retention_period)

### Queues (SQS)

- **Recovery method**: No recovery needed — messages are durable in SQS for 14 days
- **RPO**: 0 (messages persisted across AZs)
- **RTO**: 0 (SQS is regional, multi-AZ by default)

### Secrets (Secrets Manager)

- **Recovery method**: 7-day recovery window prevents accidental permanent deletion
- **RPO**: 0 (Secrets Manager is multi-AZ)
- **RTO**: 0

### Object Storage (S3)

- **Recovery method**: Versioning enabled — recover from accidental deletes
- **RPO**: 0 (S3 is 11-9s durable)
- **RTO**: Instant (restore object version)

## Disaster Scenarios

### Scenario 1: Single AZ Failure

| Impact | Action |
| --- | --- |
| ECS tasks in failed AZ terminate | Autoscaling replaces in healthy AZs |
| Aurora failover (if multi-AZ) | Automatic in prod; manual restore in dev |
| No action required for SQS/S3 | Regional services unaffected |

### Scenario 2: Accidental Resource Deletion

| Resource | Protection |
| --- | --- |
| Aurora cluster | `deletion_protection = true` (prod), `skip_final_snapshot = false` (prod) |
| S3 bucket | Versioning + lifecycle, MFA delete (prod) |
| Secrets | 7-day recovery window |
| ECS services | Recreate via `terraform apply` |
| Terraform state | S3 versioning + cross-region replication |

### Scenario 3: Region-Wide Outage

| Action | Timeline |
| --- | --- |
| Assess impact and duration | 0-15 min |
| If > 1 hour: begin failover | 15-30 min |
| Deploy to us-west-2 via Terraform | 30-60 min |
| Restore Aurora from cross-region backup | 30-60 min |
| Update DNS (Route53 failover) | 5 min |

**Note**: Cross-region DR is not deployed for dev. Terraform code is portable —
change `aws_region` and apply in the DR region.

## Game Day Plan

### Objective

Validate that the platform can recover from common failure scenarios
within stated RPO/RTO targets.

### Exercises (Quarterly)

1. **Aurora restore test**: Stop cluster, restore from backup, verify data integrity
1. **ECS task kill**: Terminate all tasks in a service, measure recovery time
1. **DLQ replay**: Intentionally fail messages, practice DLQ investigation + replay
1. **Full environment rebuild**: `terraform destroy` + `terraform apply` in a test account
1. **Secret rotation**: Rotate a secret, verify ECS tasks pick up new value

### Success Criteria

- All exercises complete within RTO targets
- No data loss beyond RPO thresholds
- Runbooks accurate and complete (update if gaps found)
- No manual steps that aren't documented

## Backup Schedule Summary

| Resource | Frequency | Retention (Dev) | Retention (Prod) |
| --- | --- | --- | --- |
| Aurora (AWS Backup) | Daily 3 AM + Monthly 1st | 7 days / 35 days | 35 days / 365 days |
| Aurora (PITR) | Continuous | 7 days | 35 days |
| Terraform state (S3) | On every apply | Versioned (infinite) | Versioned + replicated |
| Secrets Manager | On change | 7-day recovery window | 30-day recovery window |
