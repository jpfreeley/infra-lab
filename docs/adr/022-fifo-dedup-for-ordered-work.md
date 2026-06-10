# ADR-022: FIFO Queue with Content-Based Dedup

## Status

Accepted

## Context

Some jobs require strict ordering and exactly-once processing.
Standard SQS provides at-least-once delivery with best-effort ordering.

## Decision

A dedicated FIFO queue for ordered workloads:

- Content-based deduplication (no explicit dedup ID needed)
- `deduplication_scope = messageGroup` (per-group dedup, not queue-wide)
- `fifo_throughput_limit = perMessageGroupId` (high throughput per group)

Standard queues rely on application-level idempotency for at-least-once semantics.

## Consequences

- Strict FIFO ordering within a message group
- Duplicate messages automatically rejected (5-minute dedup window)
- High throughput mode avoids the 300 msg/s FIFO limit per queue
- Slightly higher cost than standard queues
- Application must use message groups correctly for ordering guarantees
