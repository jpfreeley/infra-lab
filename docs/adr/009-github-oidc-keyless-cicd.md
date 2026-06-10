# ADR-009: GitHub OIDC for Keyless CI/CD

## Status

Accepted

## Context

CI/CD pipelines need AWS access to deploy infrastructure. Traditional approach
uses stored access keys. Modern approach uses OIDC federation.

## Decision

GitHub Actions authenticates to AWS via OIDC:

- OIDC provider: `token.actions.githubusercontent.com`
- Deploy role scoped to `repo:jpfreeley/infra-lab` (main + PRs only)
- No static AWS credentials in GitHub secrets
- Role trust restricts to specific branches/events

## Consequences

- Zero long-lived credentials in CI/CD
- Credentials automatically rotate (per-job tokens)
- Audit trail shows exact repo, branch, and workflow that assumed the role
- Requires careful trust policy scoping to prevent unauthorized branches
