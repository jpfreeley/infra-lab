# ADR-012: ECS Fargate with Dual Cluster Model

## Status

Accepted

## Context

ECS workloads span two planes with different reliability and cost requirements.
Can use a single cluster with task-level isolation or separate clusters.

## Decision

Two ECS clusters:

- **Control cluster**: On-demand Fargate only (reliability for API)
- **Execution cluster**: Fargate + Fargate Spot (3:1 ratio for cost optimization)

## Consequences

- Control plane services never interrupted by Spot reclamation
- Execution plane saves ~70% on compute via Spot for fault-tolerant workers
- Separate clusters provide independent capacity provider strategies
- Container Insights enabled on both for per-cluster visibility
