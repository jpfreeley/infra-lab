# ADR-005: Control Tower for Governance Baseline

## Status

Accepted

## Context

A new AWS Organization needs baseline governance: account provisioning,
guardrails, centralized logging, and security services. Can be done manually
or via Control Tower.

## Decision

Use AWS Control Tower Landing Zone (v4.0) for baseline governance:

- Manages Organization Trail, Config, and centralized logging
- Provides guardrails (preventive + detective)
- Account Factory for standardized provisioning

OUs, SCPs, and advanced services managed separately via Terraform (not CT manifest).

## Consequences

- Fast baseline setup with best-practice defaults
- Some resources owned by CT cannot be modified by Terraform (e.g., CT CloudTrail KMS key)
- OU management must use native Terraform resources (CT manifest doesn't support OUs)
- Control Tower updates are slow (~24 min) and must use precise manifest JSON
