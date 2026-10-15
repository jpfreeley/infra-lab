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
- Session-based credentials (max 8h for PlatformEngineer, Developer, SecurityAuditor,
  and ReadOnly; max 12h for Admin as of 2026-10-01 — see below)

## Consequences

- Zero static credentials for humans
- Centralized access management and audit
- Break-glass requires SSO availability (mitigated by OrganizationAccountAccessRole)
- Permission sets limited to AWS managed policies + custom inline policies

## Admin Session Duration Raised to 12h (2026-10-01)

JP's day-to-day `infra-lab`/`infra-lab-mempalace` CLI work runs on the
`AdministratorAccess` permission set, not just true break-glass use. Its
original 4h `session_duration` meant re-authenticating via browser SSO login
multiple times within one working session. Raised to `PT12H` in
`infra/mgmt/org/sso.tf` — AWS's hard ceiling for a permission set's session
duration; it cannot go higher. Still fully temporary, rotating STS
credentials, same security model as before, just a longer rotation window.

The other four permission sets (PlatformEngineer, Developer, SecurityAuditor,
ReadOnly) are unchanged at 8h, matching their original, more occasional-use
intent.
