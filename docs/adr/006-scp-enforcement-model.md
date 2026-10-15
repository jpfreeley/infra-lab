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

## Control Tower's Own Guardrail SCPs Don't Honor the Admin Exemption (2026-10-15)

Found live while trying to add a `DenyInsecureTransport` bucket policy to
every S3 bucket in the org: Control Tower's own preventive guardrail SCP
(`p-rfhbth3m`, attached to the Security OU covering the log-archive and
security-audit accounts) includes a statement
(`GRAUDITBUCKETPOLICYCHANGESPROHIBITED`) that denies `s3:PutBucketPolicy` on
**every resource** in those accounts, for any principal other than
`AWSControlTowerExecution`. The exemption list in this ADR's own Decision
section (`AWSReservedSSO_AWSAdministratorAccess_*`) does **not** apply here —
this is a guardrail SCP that Control Tower manages directly, separate from
the hand-written org SCPs this ADR otherwise describes, and it does not carry
the same admin exemption.

Confirmed via `aws organizations describe-policy` on the real SCP, not by
guessing from the error message alone. The deny is categorical (`Resource:
"*"`, not scoped to Control-Tower-named buckets only) — every bucket in those
two accounts is out of reach for a policy change via any normal admin path,
by design. This is correct behavior for protecting audit/log accounts, not a
bug: don't try to work around it with a different role or a direct API call,
and don't assume the Decision section's admin exemption covers every SCP in
the org just because it covers the hand-written ones.
