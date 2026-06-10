# ADR-015: Scale-from-Zero in Dev for Cost Optimization

## Status

Accepted

## Context

Dev environment is idle most of the time. Running ECS tasks 24/7 wastes
~$55/mo on workers that process zero messages.

## Decision

Dev environment uses scale-from-zero for all workers:

- `desired_count = 0` for all worker services
- `min_capacity = 0` in autoscaling
- API service: single task (`desired_count = 1`, `min_capacity = 1`)
- Workers scale up automatically when autoscaling triggers fire

ECS service lifecycle ignores `desired_count` changes, so manual CLI scaling
persists across Terraform applies.

## Consequences

- Idle cost reduced from ~$86/mo to ~$31/mo
- Workers have cold-start latency when scaling from zero (~30-60s)
- Acceptable for dev; prod will maintain warm minimums
- Manual scale-up available via `aws ecs update-service --desired-count N`
