# ADR-021: Step Functions for Job Orchestration

## Status

Accepted

## Context

Multi-step jobs need orchestration: validate, route, process, notify.
Options: chain SQS messages, custom orchestrator service, or Step Functions.

## Decision

Use AWS Step Functions (Standard type) for job lifecycle orchestration:

- State machine: ValidateInput → RouteByTier → SendToQueue → WaitForCompletion → Notify
- X-Ray tracing for distributed visibility
- CloudWatch logging for debugging
- IAM role scoped to SQS send + X-Ray

## Consequences

- Visual workflow execution history (no custom logging needed)
- Built-in retry, timeout, and error handling
- Pay-per-state-transition ($0.025 per 1000 transitions) — near zero in dev
- Complex workflows are declarative (JSON) rather than imperative code
- 25,000 events/execution limit for Standard type (sufficient for orchestration)
