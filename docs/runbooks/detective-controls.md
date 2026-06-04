# Detective Controls Runbooks (E03-S019)

## Overview

This document provides response procedures for findings from the organization's detective control services: GuardDuty, Security Hub, and AWS Config.

---

## GuardDuty Findings

### GuardDuty Triage Process

1. **Check Severity**: High/Critical findings require immediate response
2. **Identify Account**: Determine which member account generated the finding
3. **Review Finding Type**: Map to the response procedure below

### Common Finding Types

| Finding Type | Severity | Response |
| ------------ | -------- | -------- |
| UnauthorizedAccess:IAMUser/MaliciousIPCaller | High | Disable credentials, investigate access logs |
| Recon:EC2/PortProbeUnprotectedPort | Medium | Review security group, check for exposed services |
| CryptoCurrency:EC2/BitcoinTool.B | High | Isolate instance, investigate compromise |
| Persistence:IAMUser/AnomalousBehavior | Medium | Review IAM activity, check for unauthorized changes |

### GuardDuty Response Steps

1. Navigate to GuardDuty console in the delegated admin account (`172134854767`)
2. Filter by severity and time range
3. For HIGH findings:
   - Contain: Isolate affected resources (revoke credentials, remove from SG)
   - Investigate: Review CloudTrail logs for the affected principal
   - Remediate: Remove unauthorized access, patch vulnerability
   - Document: Record findings and actions in incident log

### GuardDuty CLI Access

```bash
# List high-severity findings (delegated admin)
aws guardduty list-findings \
  --detector-id 80ce656eaede5e533ce9b198fe16f3cd \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}' \
  --profile infra-lab-log-archive
```

---

## Security Hub Findings

### Security Hub Triage Process

1. **Check Standard**: Which compliance standard flagged the finding?
2. **Review Resource**: Identify the non-compliant resource
3. **Determine Fix**: Reference the remediation guidance

### Standards Enabled

- AWS Foundational Security Best Practices (FSBP)
- CIS AWS Foundations Benchmark v1.2.0

### Security Hub Response Steps

1. Navigate to Security Hub in the delegated admin account (`881413600100`)
2. Filter by compliance status = FAILED
3. Group by resource type for bulk remediation
4. For each finding:
   - Review the specific control and remediation steps
   - Determine if it's a true finding or acceptable risk
   - If acceptable: Add a suppression with justification
   - If actionable: Create a fix PR in the relevant Terraform root

### Security Hub CLI Access

```bash
# Get failed findings (audit account)
aws securityhub get-findings \
  --filters '{"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}]}' \
  --max-items 10 \
  --profile infra-lab-security-audit
```

---

## AWS Config Non-Compliance

### Config Triage Process

1. **Check Rule**: Which Config rule flagged non-compliance?
2. **Identify Resource**: What resource is out of compliance?
3. **Assess Impact**: Is this a security risk or governance gap?

### Organization Conformance Pack Rules

Our `infra-lab-security-baseline` conformance pack checks:

- S3: encryption, public access, versioning, logging
- EC2/EBS: encryption
- RDS: storage encryption
- CloudTrail: enabled, encrypted, multi-region
- Root: MFA, no access keys
- IAM: password policy
- VPC: flow logs
- Security Groups: no unrestricted SSH
- Tags: required tags on EC2 and S3

### Config Response Steps

1. Navigate to AWS Config in the member account
2. Filter by compliance status = NON_COMPLIANT
3. For each resource:
   - If Terraform-managed: Update the Terraform code and apply
   - If manually created: Either import to Terraform or remediate directly
   - If Control Tower-managed: Document as known limitation

### Config CLI Access

```bash
# Check conformance pack compliance (log-archive)
aws configservice get-conformance-pack-compliance-summary \
  --conformance-pack-names OrgConformsPack-infra-lab-security-baseline-15lssxz6 \
  --profile infra-lab-log-archive
```

---

## Escalation

| Severity | Response Time | Escalation |
| -------- | ------------- | ---------- |
| Critical | 1 hour | Immediate action, notify owner |
| High | 4 hours | Same-day response |
| Medium | 24 hours | Next business day |
| Low | 1 week | Batch with routine maintenance |

## References

- GuardDuty delegated admin: `172134854767` (Log Archive)
- Security Hub delegated admin: `881413600100` (Audit)
- Config conformance pack: `infra-lab-security-baseline`
- CloudTrail log group: `/aws/cloudtrail/infra-lab-org-trail`
