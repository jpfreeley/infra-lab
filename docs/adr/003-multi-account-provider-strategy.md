# ADR-003: Multi-Account Provider + AssumeRole

## Status

Accepted

## Context

The platform spans multiple AWS accounts (management, workload, security).
Terraform needs a consistent way to deploy resources across accounts without
storing credentials for each.

## Decision

Use AWS provider with AssumeRole for cross-account access:

- Default provider authenticates to the management account (via SSO profile)
- Aliased providers assume roles into target accounts
- CI/CD uses OIDC → deploy role → AssumeRole chain

## Consequences

- No static credentials stored anywhere
- Audit trail shows which role assumed into which account
- Provider aliases add complexity but enable multi-account in single root
- Session duration must be sufficient for long applies (8h for SAML)
