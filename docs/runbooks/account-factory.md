# Account Factory Customization (E03-S016)

## Overview

AWS Control Tower Account Factory provisions new member accounts with baseline configurations. This document describes the customization strategy for infra-lab.

## Current Account Factory Configuration

Account Factory is managed by Control Tower and provisions accounts with:

- AWS Config Recorder (enabled by default)
- CloudTrail integration (Organization Trail)
- GuardDuty enrollment (auto-enabled via delegated admin)
- Security Hub enrollment (auto-enabled via delegated admin)
- VPC (default, can be customized)

## Account Provisioning Strategy

### Standard Account Request

| Field | Convention |
| ----- | ---------- |
| Account Name | `{purpose}` (e.g., `prod`, `staging`, `shared-services`) |
| Email | `jpf.{purpose}@gmail.com` (dot-separated variant) |
| OU | Based on purpose: Workloads, Infrastructure, Sandbox |
| SSO User | Not provisioned (use group-based access) |

### Post-Provisioning Baseline

After Control Tower provisions an account, apply these via Terraform:

1. **IAM Password Policy** — Applied org-wide via `iam_password_policy.tf`
2. **Tag Policy** — Applied org-wide at org root
3. **SCPs** — Applied based on OU membership
4. **Config Conformance Pack** — Auto-deployed via org conformance pack
5. **Backup Policy** — Applied org-wide at org root

### VPC Configuration

Control Tower creates a default VPC. For workload accounts:

- Delete the default VPC (E05 will provision purpose-built VPCs)
- Or: Leave default VPC and add proper networking via Terraform

## Customization Patterns

### Using Account Factory Customization (AFC)

AFC can deploy CloudFormation StackSets to new accounts on provisioning. Current approach:

- **Not using AFC** for now — post-provisioning is handled via Terraform
- Future consideration: Use AFC for bootstrapping a Terraform execution role

### Terraform Account Baseline Module (Future)

When E04 is complete (GitHub OIDC + CI/CD auth), a Terraform module will handle:

- Terraform execution role creation
- Provider configuration for the new account
- Network baseline (E05)
- Compute baseline (E06)

## Account Inventory

| Account ID | Name | OU | Purpose |
| ---------- | ---- | -- | ------- |
| 551452024305 | Management | Root | Org management, Control Tower |
| 172134854767 | Log Archive | Security | Centralized logging, GuardDuty delegated admin |
| 881413600100 | Audit | Security | Security Hub delegated admin |
| 970353898303 | test-env | Sandbox | Experimentation |

## Guardrails Applied to New Accounts

All new accounts automatically receive (based on OU):

- Deny leave organization (org root)
- Tag policy enforcement (org root)
- Backup policy (org root)
- Security service protection SCP (if in Workloads/Infrastructure/Security/Sandbox)
- IAM user prevention SCP (if in Workloads/Sandbox)
- Region restriction SCP (if in Workloads)
- Config conformance pack (if Config Recorder enabled)

## Future Enhancements

- E04: GitHub OIDC provider + Terraform execution role per account
- E05: Standardized VPC provisioning per account
- AFC integration for zero-touch account baseline
