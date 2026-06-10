# ADR-029: RDS Auto-Stop Mechanism via EventBridge + Lambda

## Status

Accepted

## Context

Aurora clusters stopped via `aws rds stop-db-cluster` auto-restart after 7 days
(AWS-enforced behavior, cannot be disabled). This creates a cost trap: clusters
intended to remain stopped silently restart and accumulate ~$44/mo per cluster
until noticed.

## Decision

Deploy an EventBridge + Lambda mechanism that automatically re-stops clusters
when they start:

- EventBridge rule matches `RDS DB Cluster Event` with message prefix
  `DB cluster started`
- Lambda reads SSM parameter `/infra-lab/rds-auto-stop/enabled`
- If `true` (default): immediately calls `rds:StopDBCluster`
- If `false`: cluster remains running (developer override)

SSM parameter uses `lifecycle { ignore_changes = [value] }` so CLI overrides
persist across Terraform applies without drift.

## Consequences

- Aurora clusters stay stopped indefinitely (not just 7 days)
- Eliminates $88/mo surprise cost from forgotten auto-restarts
- Developers must explicitly disable auto-stop when they need clusters running
- ~30-second delay between start and re-stop (cluster briefly available)
- Lambda cost: $0/mo (free tier, invoked at most once per 7 days per cluster)
- SSM parameter change is instant — no deployment needed to toggle behavior
