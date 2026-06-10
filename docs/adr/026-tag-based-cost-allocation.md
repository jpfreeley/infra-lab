# ADR-026: Tag-Based Cost Allocation

## Status

Accepted

## Context

Cost visibility requires attribution of AWS spend to environments, services,
and teams. Options: account-per-environment, tag-based allocation, or both.

## Decision

Tag-based cost allocation enforced at multiple layers:

1. Org tag policy enforces `Project`, `ManagedBy`, `Environment`
1. Provider default_tags applies to all resources automatically
1. Module `common_tags` ensures consistent tagging
1. Cost Explorer activated cost allocation tags

## Consequences

- Single account can show per-environment and per-service costs
- No additional accounts needed for cost isolation in dev
- Tag compliance enforced by org policy (non-compliant resources get warnings)
- AWS Cost Explorer grouping by tag enables chargeback reporting
- Requires discipline: every new resource must receive tags (enforced by module pattern)
