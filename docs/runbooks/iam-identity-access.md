# IAM Identity and Access Runbook (E04)

## Break-Glass Access Pattern (S004)

### When to Use

Break-glass access is reserved for emergency situations when normal SSO access is unavailable or insufficient:

- IAM Identity Center is down or misconfigured
- Need to recover from a lockout scenario
- Critical production incident requiring immediate elevated access

### Procedure

1. **Authenticate via SSO** using the `AdministratorAccess` permission set (4h session)
2. **If SSO is unavailable**, use the `OrganizationAccountAccessRole` from the Management account console
3. **Document** all actions taken during break-glass access in an incident log
4. **Notify** the security team within 1 hour of break-glass usage

### Roles Available for Break-Glass

- `OrganizationAccountAccessRole` - exists in all member accounts, trusted by Management
- `AWSReservedSSO_AWSAdministratorAccess_*` - SSO admin role (exempt from all SCPs)
- `AWSControlTowerExecution` - Control Tower automation role

### MFA Requirements (S011)

All console access via SSO requires the Identity Center MFA configuration. Break-glass
roles inherit the SSO MFA enforcement. Root account access requires hardware MFA token.

---

## Role Chaining for CI/CD (S007)

### Architecture

```text
GitHub Actions (OIDC token)
  |
  v
infra-lab-github-actions-deploy (Management account, 551452024305)
  |
  v (sts:AssumeRole)
Target account deploy role (future: per-account Terraform execution role)
```

### Current State

The GitHub OIDC deploy role is scoped to the Management account with AdministratorAccess.
For multi-account deployments (E05+), target account roles will be created that trust
this role for cross-account access.

### Future: Per-Account Deploy Roles

When workload accounts are provisioned:

```hcl
resource "aws_iam_role" "terraform_execution" {
  name = "infra-lab-terraform-execution"
  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::551452024305:role/infra-lab-github-actions-deploy" }
      Action    = "sts:AssumeRole"
    }]
  })
}
```

---

## Session Tagging for CI Deploys (S008)

GitHub Actions OIDC tokens automatically include claims that appear in CloudTrail:

- `sub`: `repo:jpfreeley/infra-lab:ref:refs/heads/main`
- `actor`: GitHub username that triggered the workflow
- `workflow`: Workflow name
- `run_id`: Unique workflow run identifier

These are visible in CloudTrail under `userIdentity.sessionContext.webIdFederationData`.

---

## Permission Boundaries (S009)

### Baseline Strategy

Permission boundaries are not yet deployed. The current enforcement model uses:

- SCPs for preventative guardrails (org-wide)
- OIDC conditions for CI/CD scope (repo-level)
- Managed policy attachments for permission sets (role-level)

### Future Enhancement

When workload accounts have developer-created roles, a permission boundary will ensure
developers cannot escalate beyond their intended scope:

```hcl
resource "aws_iam_policy" "developer_boundary" {
  name   = "developer-permission-boundary"
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:*", "ecs:*", "s3:*", "dynamodb:*", "logs:*", "cloudwatch:*"]
      Resource = "*"
    }, {
      Effect   = "Deny"
      Action   = ["iam:*", "organizations:*", "account:*"]
      Resource = "*"
    }]
  })
}
```

---

## IAM Access Analyzer (S010)

An organization-level IAM Access Analyzer is deployed (`infra-lab-org-analyzer`).
It continuously monitors for:

- Resources shared with external accounts
- Unused IAM permissions (for least-privilege refinement)
- Policy validation errors

### Reviewing Findings

```bash
aws accessanalyzer list-findings \
  --analyzer-arn arn:aws:access-analyzer:us-east-1:551452024305:analyzer/infra-lab-org-analyzer \
  --profile infra-lab
```

---

## Root User Restrictions (S012)

An SCP (`deny-root-user`) blocks root user IAM, Organizations, Account, and Billing
actions in the Workloads, Sandbox, and Infrastructure OUs. Root usage is only permitted
in the Management account for true break-glass scenarios.

---

## Third-Party Vendor Access (S013)

### Current Policy

No third-party vendors currently have access. When needed:

1. Create a dedicated IAM role with time-bounded trust (use `Condition` with `aws:CurrentTime`)
2. Use external ID in the trust policy for cross-account access
3. Scope permissions to exactly what the vendor needs
4. Set a calendar reminder for access review/rotation
5. Document in MEMORY.md under vendor access section

---

## IAM Policy Testing (S014)

### Approach

IAM policy validation is handled by:

- `checkov` - static analysis of IAM policies in Terraform
- IAM Access Analyzer - policy validation API
- `terraform plan` - shows exact policy document before apply
- Config conformance pack - `iam-password-policy` rule

### Future: IAM Policy Testing

Add `terraform test` with IAM policy simulator for permission set validation.

---

## CloudTrail Insights (S015)

CloudTrail Insights event data store is configured to detect anomalous API activity
patterns. Insights automatically baseline normal API call volumes and alert on deviations.

Insights events are stored for 90 days in the `infra-lab-insights-events` data store.

---

## Terraform State Access (S016)

### Current Access Model

Terraform state is stored in `infra-lab-tf-state-551452024305` with:

- SSE-KMS encryption (customer-managed key)
- DynamoDB state locking
- Versioning enabled (90-day noncurrent expiry)
- Cross-region replication

### Who Can Access State

- SSO `AdministratorAccess` and `PlatformEngineer` permission sets
- GitHub Actions deploy role (`infra-lab-github-actions-deploy`)
- `OrganizationAccountAccessRole` (break-glass)

### Future: Least-Privilege State Policy

A dedicated IAM policy restricting state access to only the S3/DynamoDB resources needed:

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::infra-lab-tf-state-551452024305",
    "arn:aws:s3:::infra-lab-tf-state-551452024305/*"
  ]
}
```

---

## OIDC Subject Conditions (S017)

The GitHub OIDC trust policy is tightened to only allow:

- `repo:jpfreeley/infra-lab:ref:refs/heads/main` - pushes to main
- `repo:jpfreeley/infra-lab:pull_request` - PR workflows

This prevents arbitrary branch workflows from assuming the deploy role.

---

## SSO Audit (S018)

### Current Audit Sources

- CloudTrail logs all SSO authentication events
- IAM Access Analyzer monitors for external access
- Security Hub checks for IAM best practices

### Manual Audit Checklist

1. Review active permission set assignments: `aws sso-admin list-account-assignments`
2. Check for unused permission sets
3. Verify group membership matches expected access
4. Review CloudTrail for unusual SSO session patterns
5. Check Access Analyzer for new findings
