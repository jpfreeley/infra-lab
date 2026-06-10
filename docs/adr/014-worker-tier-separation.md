# ADR-014: Worker Tiers with Independent Scaling

## Status

Accepted

## Context

Worker tasks have vastly different resource requirements — from lightweight
notifications (256 CPU) to heavy ML inference (4096 CPU). A single worker
pool would waste resources or starve small tasks.

## Decision

Three worker tiers with independent ECS services and autoscaling:

- **Nano** (256 CPU / 512 MiB): notifications, webhooks
- **Medium** (1024 CPU / 2048 MiB): data transforms, reports
- **XLarge** (4096 CPU / 8192 MiB): ML inference, batch processing

Each tier has its own SQS queue, autoscaling target, and ECS service.

## Consequences

- Right-sized resources per workload type (cost efficient)
- Independent scaling — xlarge doesn't block nano tasks
- More infrastructure to manage (3 services, 3 queues, 3 scaling policies)
- New workload types can be added by creating a new tier
