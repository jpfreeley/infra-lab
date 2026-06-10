# ADR-007: Delegated Admin for Security Services

## Status

Accepted

## Context

GuardDuty, Security Hub, and other security services can be managed centrally
from the management account or delegated to a security account.

## Decision

Delegate administration to dedicated accounts:

- GuardDuty → Log Archive account
- Security Hub → Audit account (finding aggregation)
- IAM Access Analyzer → Management account (organization-level)

## Consequences

- Management account has minimal direct service configuration
- Delegated accounts manage org-wide settings for their respective services
- Requires provider aliases in Terraform (dual-provider model)
- Once delegated, management account cannot modify org-wide config for that service
