# ADR-016: Aurora Serverless v2 over Provisioned

## Status

Accepted

## Context

The platform needs PostgreSQL databases. Options: RDS provisioned instances,
Aurora provisioned, Aurora Serverless v1 (deprecated), Aurora Serverless v2.

## Decision

Use Aurora Serverless v2 (PostgreSQL 15.4):

- Min capacity: 0.5 ACU (dev), higher in prod
- Max capacity: 4-8 ACU (scales with demand)
- Single instance per cluster in dev, 2+ in prod for HA

## Consequences

- Scales ACUs automatically with load (no capacity planning needed)
- Minimum 0.5 ACU = ~$44/mo per cluster (cannot go lower)
- Clusters can be stopped when idle (eliminates ACU charge, keeps storage)
- Compatible with all PostgreSQL features (RLS, extensions, pgaudit)
- Storage billed separately ($0.10/GB-month)
