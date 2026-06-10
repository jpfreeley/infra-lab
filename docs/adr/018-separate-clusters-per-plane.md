# ADR-018: Separate DB Clusters per Plane

## Status

Accepted

## Context

Control plane (API, orchestration state) and execution plane (tenant workloads,
worker data) have different data isolation, scaling, and security requirements.

## Decision

Separate Aurora clusters per plane:

- **Control cluster**: API state, orchestration metadata, config
- **Execution cluster**: Tenant workload data, job results, processing state

Each cluster has its own subnet group, security group, and IAM roles.

## Consequences

- Strong data isolation between planes (no cross-contamination)
- Independent scaling (execution cluster gets higher max ACU for batch jobs)
- Noisy-neighbor prevention (heavy batch job can't starve API queries)
- Double the Aurora cost ($88/mo minimum vs $44/mo for shared)
- Mitigated by stopping clusters when idle
