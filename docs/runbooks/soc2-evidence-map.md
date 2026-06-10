# SOC2 Evidence Map

## Overview

This document maps SOC2 Trust Service Criteria to AWS controls implemented
in the infra-lab platform. Evidence is automatically collected via AWS native
services (CloudTrail, Config, Security Hub, GuardDuty).

## Trust Service Criteria Mapping

### CC1 — Control Environment

| Criteria | Control | Evidence Source | Epic |
| --- | --- | --- | --- |
| CC1.1 | CODEOWNERS + PR review | GitHub audit log | E01 |
| CC1.2 | IAM Identity Center roles | CloudTrail | E04 |
| CC1.3 | Org tag policies enforced | AWS Organizations | E03 |

### CC2 — Communication and Information

| Criteria | Control | Evidence Source | Epic |
| --- | --- | --- | --- |
| CC2.1 | Structured logging (JSON) | CloudWatch Logs | E10 |
| CC2.2 | Incident response runbook | docs/runbooks/ | E12 |
| CC2.3 | Change management via PRs | GitHub PR history | E01 |

### CC3 — Risk Assessment

| Criteria | Control | Evidence Source | Epic |
| --- | --- | --- | --- |
| CC3.1 | GuardDuty threat detection | GuardDuty findings | E03 |
| CC3.2 | Security Hub scoring | Security Hub | E03 |
| CC3.3 | IAM Access Analyzer | Access Analyzer findings | E04 |

### CC5 — Control Activities

| Criteria | Control | Evidence Source | Epic |
| --- | --- | --- | --- |
| CC5.1 | SCPs prevent dangerous actions | AWS Organizations | E03 |
| CC5.2 | Least-privilege IAM roles | IAM policies (Terraform) | E04, E06 |
| CC5.3 | MFA enforced (SSO) | IAM Identity Center config | E04 |

### CC6 — Logical and Physical Access

| Criteria | Control | Evidence Source | Epic |
| --- | --- | --- | --- |
| CC6.1 | Network segmentation (dual VPC) | VPC flow logs | E05 |
| CC6.2 | Security groups (least privilege) | Config rules | E05 |
| CC6.3 | Encryption at rest (KMS) | Config conformance pack | E03 |
| CC6.4 | Encryption in transit (TLS 1.3) | ALB policy | E06 |
| CC6.5 | Secrets Manager (no static creds) | Secrets Manager audit | E09 |
| CC6.6 | OIDC (no long-lived keys in CI) | GitHub OIDC provider | E04 |

### CC7 — System Operations

| Criteria | Control | Evidence Source | Epic |
| --- | --- | --- | --- |
| CC7.1 | CloudWatch alarms | CloudWatch | E10 |
| CC7.2 | Cost anomaly detection | Cost Explorer | E11 |
| CC7.3 | Automated backups | AWS Backup | E12 |
| CC7.4 | Blue/green deployments | CodeDeploy history | E06 |

### CC8 — Change Management

| Criteria | Control | Evidence Source | Epic |
| --- | --- | --- | --- |
| CC8.1 | IaC (Terraform) for all changes | Git history + state | E02 |
| CC8.2 | CI/CD pipeline (no manual deploy) | GitHub Actions | E01 |
| CC8.3 | Pre-commit hooks (lint, scan, validate) | Pre-commit config | E01 |
| CC8.4 | Checkov security scanning | CI output | E01 |

### CC9 — Risk Mitigation

| Criteria | Control | Evidence Source | Epic |
| --- | --- | --- | --- |
| CC9.1 | DR strategy documented | docs/runbooks/ | E12 |
| CC9.2 | Backup retention policies | AWS Backup plan | E12 |
| CC9.3 | Deletion protection (prod) | Terraform config | E06, E07 |

## Evidence Collection

### Automated (Always Running)

| Service | What It Collects | Retention |
| --- | --- | --- |
| CloudTrail | All API calls across org | 90 days (event history) + S3 indefinite |
| AWS Config | Resource configuration timeline | Continuous |
| Security Hub | Compliance scores (CIS, FSBP) | 90 days |
| GuardDuty | Threat findings | 90 days |
| CloudWatch Logs | Application + infrastructure logs | 14-30 days (configurable) |

### On-Demand (Auditor Requests)

| Evidence | How to Produce |
| --- | --- |
| IAM access review | `aws iam get-credential-report` + Access Analyzer |
| Network diagram | Export from VPC console or generate from Terraform |
| Encryption inventory | Config rule: `encrypted-volumes`, `rds-storage-encrypted` |
| Backup compliance | AWS Backup audit report |
| Change history | `git log` + GitHub PR history |

## Audit Preparation Checklist

1. Export Security Hub compliance report (CIS + FSBP scores)
1. Generate IAM credential report
1. Export CloudTrail events for audit period
1. Screenshot CloudWatch dashboards
1. Export AWS Backup job history
1. Collect GitHub PR merge history for audit period
1. Export Config conformance pack compliance
