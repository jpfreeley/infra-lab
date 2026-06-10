# ADR-006: SCP Enforcement with Break-Glass Exemptions

## Status

Accepted

## Context

Service Control Policies prevent dangerous actions across the organization.
But overly restrictive SCPs can lock out administrators during emergencies.

## Decision

SCPs enforce preventive controls with explicit exemptions for:

- `AWSControlTowerExecution` (Control Tower automation)
- `AWSCloudFormationStackSetExecutionRole` (StackSets)
- `OrganizationAccountAccessRole` (break-glass)
- `AWSReservedSSO_AWSAdministratorAccess_*` (IAM Identity Center admin)

Policies applied: IAM user prevention, security service protection, region restriction,
root user blocking (in workload OUs).

## Consequences

- Dangerous actions blocked by default across all member accounts
- Break-glass access preserved for emergencies
- SCPs don't apply to management account (AWS limitation)
- Must test SCP changes carefully — overly broad policies can lock out automation
