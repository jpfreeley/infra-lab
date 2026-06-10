# ADR-024: Private CA Deferred (Cost)

## Status

Accepted

## Context

Service-to-service mTLS requires a Private Certificate Authority to issue
short-lived certificates. AWS Private CA costs $400/mo per CA.

## Decision

Defer Private CA and mTLS implementation:

- Root CA + Issuing CA = $800/mo — not justified for a lab environment
- Architecture fully documented for future implementation
- When needed: root CA in security account, issuing CA shared via RAM,
  ACM private cert issuance, mTLS on ALB

## Consequences

- Saves $800/mo in the lab environment
- No service-to-service certificate authentication currently
- Security relies on: VPC isolation, security groups, IAM roles
- Must implement before production workloads that require mTLS
- Full architecture documented — implementation is straightforward when funded
