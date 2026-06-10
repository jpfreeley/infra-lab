# ADR-019: RDS-Managed Master Passwords

## Status

Accepted

## Context

Aurora clusters need master passwords. Options: static password in Terraform,
random password with Secrets Manager, or RDS-managed passwords.

## Decision

Use `manage_master_user_password = true` on Aurora clusters:

- RDS creates and stores the master password in Secrets Manager
- Automatic rotation managed by RDS (no Lambda needed)
- Secret ARN exposed as output for RDS Proxy auth

## Consequences

- No passwords in Terraform state or code
- Automatic rotation without custom Lambda functions
- Password never visible to operators (managed entirely by AWS)
- Application access via RDS Proxy using the managed secret ARN
- Secret costs $0.40/mo per secret
