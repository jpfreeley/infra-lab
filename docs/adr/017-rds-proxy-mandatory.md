# ADR-017: RDS Proxy Mandatory for ECS Workloads

## Status

Accepted

## Context

ECS tasks create many short-lived database connections. During scaling events,
connection storms can exhaust Aurora's connection limit (causing failures for
all tasks). Connection pooling is needed.

## Decision

RDS Proxy is mandatory between ECS services and Aurora:

- Pool configuration: 80% max connections, 50% idle, 120s borrow timeout
- TLS required for all proxy connections
- Auth via Secrets Manager (no credentials in connection strings)
- No session pinning (compatible with RLS via SET ROLE)

Proxy omitted from dev for cost optimization (ECS tasks connect directly
when running). Module available for staging/prod.

## Consequences

- Eliminates connection storm failures during ECS scaling
- Transparent to application code (same PostgreSQL protocol)
- Adds ~$11/mo per proxy instance
- Proxy must be in same subnets as Aurora (data tier)
- Omitted from dev saves $22/mo; must add before load testing
