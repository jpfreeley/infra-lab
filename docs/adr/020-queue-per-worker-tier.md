# ADR-020: Queue per Worker Tier

## Status

Accepted

## Context

Workers of different tiers (nano, medium, xlarge) process messages at
vastly different speeds. A single queue would require a compromise
visibility timeout and mixing fast/slow jobs.

## Decision

Dedicated SQS queue per worker tier:

- Nano: 2-min visibility timeout
- Medium: 5-min visibility timeout
- XLarge: 15-min visibility timeout

Each queue has its own DLQ (14-day retention, max 2-3 retries).

## Consequences

- Visibility timeout tuned per tier (no compromise)
- Fast nano jobs not blocked behind slow xlarge jobs
- Independent DLQ monitoring per tier (different failure profiles)
- More queues to manage (4 main + 4 DLQs) but clear separation
- Autoscaling can target queue depth per tier independently
