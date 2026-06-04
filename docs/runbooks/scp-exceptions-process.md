# SCP Exceptions Process (E03-S017)

## Overview

Service Control Policies (SCPs) enforce preventative guardrails across the organization. Occasionally, legitimate operations require temporary or permanent exceptions.

## Exception Types

| Type      | Duration       | Approval                | Example                                       |
| --------- | -------------- | ----------------------- | --------------------------------------------- |
| Temporary | Up to 72 hours | Single admin approval   | Break-glass incident response                 |
| Permanent | Indefinite     | Owner + Security review | New automation role needing restricted action |

## Request Process

1. **Submit Request**: Open a GitHub Issue using the `SCP Exception` template
2. **Justification**: Document the specific SCP, action blocked, and business reason
3. **Risk Assessment**: Describe blast radius and mitigation controls
4. **Approval**: Security owner reviews and approves/denies
5. **Implementation**: Add `ArnNotLike` exemption to the SCP's condition block
6. **Validation**: Verify the exemption works without breaking other guardrails
7. **Documentation**: Update MEMORY.md with the exception details

## Current Exempt Roles

These roles are permanently exempt from all SCPs:

- `AWSControlTowerExecution` — Control Tower automation
- `AWSCloudFormationStackSetExecutionRole` — StackSets deployment
- `OrganizationAccountAccessRole` — Break-glass admin
- `AWSReservedSSO_AWSAdministratorAccess_*` — IAM Identity Center admin

## Adding an Exemption

In `infra/mgmt/org/locals.tf`, add the role ARN to `scp_exempt_role_arns`:

```hcl
variable "scp_exempt_role_arns" {
  default = ["arn:aws:iam::*:role/new-exempt-role"]
}
```

Or for a single SCP, add a condition directly in `scps.tf`.

## Revoking an Exception

1. Remove the ARN from the exemption list
2. Run `terraform plan` to verify the change
3. Apply via PR with security owner approval
4. Confirm the action is now blocked as expected

## Audit

All SCP exceptions are tracked in:

- Terraform code (`scps.tf`, `locals.tf`)
- Git history (PR trail)
- MEMORY.md (carry-forward notes)
