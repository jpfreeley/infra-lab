# ADR-025: CloudWatch-Native Observability over OTel

## Status

Accepted

## Context

Observability options: OpenTelemetry collector sidecar (vendor-neutral),
CloudWatch native metrics/logs/traces, or third-party (Datadog, Grafana).

## Decision

Use CloudWatch-native observability in dev:

- Metrics: ECS/SQS/ALB built-in metrics (no agent needed)
- Logs: `awslogs` driver directly to CloudWatch (already configured)
- Traces: X-Ray (enabled on Step Functions, available for ECS)
- Dashboards + Alarms: CloudWatch free tier (3 dashboards, 10 alarms)

OTel collector deferred to prod (adds ~$15/mo sidecar compute).

## Consequences

- Zero additional compute cost for observability in dev
- CloudWatch free tier covers dashboards and alarms
- No vendor lock-in concern for a single-environment lab
- When OTel needed: add as ECS sidecar, export to CloudWatch or third-party
- Trade-off: no custom metrics without application instrumentation
