# ADR-023: Secrets Manager for Application Secrets

## Status

Accepted

## Context

Application secrets (DB credentials, API keys, tokens) need secure storage.
Options: SSM Parameter Store (SecureString), Secrets Manager, HashiCorp Vault.

## Decision

Use AWS Secrets Manager:

- Native integration with ECS task definitions (`secrets` block)
- Native integration with RDS (managed master passwords)
- Automatic rotation support (Lambda-based)
- 7-day recovery window prevents accidental permanent deletion

## Consequences

- $0.40/mo per secret (vs free for SSM SecureString)
- Rotation built-in (SSM requires custom solution)
- ECS injects secrets as env vars at container start
- Values managed externally after Terraform bootstrap (lifecycle ignore)
- Access controlled via IAM + optional resource policies
