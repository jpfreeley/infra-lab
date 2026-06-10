# ADR-008: IAM Identity Center for All Human Access

## Status

Accepted

## Context

Human operators need AWS console and CLI access. Options: IAM users with
access keys, federated access via SAML/OIDC, or IAM Identity Center (SSO).

## Decision

All human access via IAM Identity Center:

- No IAM users or long-lived access keys (enforced by SCP)
- Role-based permission sets: Admin, PlatformEngineer, Developer, SecurityAuditor, ReadOnly
- MFA enforced at SSO layer
- Session-based credentials (max 8h)

## Consequences

- Zero static credentials for humans
- Centralized access management and audit
- Break-glass requires SSO availability (mitigated by OrganizationAccountAccessRole)
- Permission sets limited to AWS managed policies + custom inline policies
