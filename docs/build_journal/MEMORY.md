# [MEMORY.md](http://MEMORY.md)

## User Profile & Preferences

* **Shell**: `zsh`

* **Package Manager**: Homebrew (`brew`)

* **Security Conscious**: Prefers official, corporate tooling from reputable sources only.

* **Workflow Preference**: Uses GitHub CLI (`gh`) for all repo/PR management.

* **Security Stance**: Prefers strong encryption (KMS CMKs) and no random 3rd party tools.

## Local Environment & Tooling

* **gh** (GitHub CLI): Primary tool for repo/PR management.

* **terraform**: Infrastructure as Code engine (v1.7.0+).

* **pre-commit**: Framework for managing git hooks.

* **tflint**: Terraform linter.

* **checkov**: Static analysis for IaC security.

* **gitleaks**: Secret detection (Note: uses local hook due to macOS dyld compatibility).

* **aws-cli**: AWS command line interface.

* **terraform-compliance**: Moved from pre-commit to CI pipeline for plan-based compliance testing.

## Local Paths

* **Downloads Directory**: `~/Downloads`

* **Repository Root**: `~/Documents/git/public/jpfreeley/infra-lab/`

## AWS Environment Context

* **Organization Management Account ID**: `551452024305`

* **AWS Profile Name**: `infra-lab` (Primary profile for Terraform admin operations).

* **Primary Region**: `us-east-1` (N. Virginia).

* **Replica Region**: `us-west-2` (Oregon).

### AWS Caller Identity (`--profile infra-lab`)

```json
{
    "UserId": "AROAYAZI2DXYQE6O3PTRO:jpf321@gmail.com",
    "Account": "551452024305",
    "Arn": "arn:aws:sts::551452024305:assumed-role/AWSReservedSSO_AWSAdministratorAccess_eea6c19cac23d161/jpf321@gmail.com"
}
```

### AWS Administrative Access Notes

* The active administrative path for the `infra-lab` profile is IAM Identity Center / AWS SSO via the reserved role pattern `AWSReservedSSO_AWSAdministratorAccess_*`.

* Break-glass and SCP-safe exemption handling must include the IAM Identity Center administrator role pattern in addition to Control Tower execution roles, StackSets execution roles, and `OrganizationAccountAccessRole`.

## Project Backlog

* **Master Backlog File**: `backlog_granular.json`

* **Backlog URL**: [http://ypgmedia.com/infra_lab/backlog_granular.json](http://ypgmedia.com/infra_lab/backlog_granular.json)

* **Source of Truth**: This file contains the full list of Epics and Stories used to drive the project.

* **Current Epic**: E03

* **Current Story**: S011 (Log bucket immutability / Object Lock / retention guardrails)

## Repository & Workflow

* **Repository Name**: `infra-lab` (Private).

* **Monorepo Structure**: Clear boundaries: `/infra`, `/app`, `/docs`.

* **Governance**: Enforced PR-first workflow with GitHub branch protection and CODEOWNERS.

* **PR Naming Convention**: `[jpf] [<Exx-Sxxx>] <Description>`

  * `<Exx-Sxxx>` = Epic and Story number, e.g., `E01-S001`.

  * `<Description>` = Self-explanatory summary.

## Infrastructure & Security

* **Encryption**: Uses customer-managed KMS keys for S3 and DynamoDB with rotation.

* **Backend Storage**: S3 bucket `infra-lab-tf-state-551452024305`.

* **State Locking**: DynamoDB table `infra-lab-tf-state-locks`.

* **High Availability**: Cross-region replication enabled (Primary: `us-east-1`, Replica: `us-west-2`).

* **S3 Hardening**: All buckets have public access blocks and ownership controls enabled.

* **Validation**: Pre-commit hooks integrated (Terraform fmt, lint, Checkov, Gitleaks).

## Terraform & AWS Usage

* **State Management**: Successfully migrated from local to remote S3 backend.

* **Provider Standards**: Uses AWS provider (v5.x) with dedicated resources for lifecycle, versioning, and encryption.

* **Resource Handling**: AWS Organizations resource is imported if already existing.

## Notes for Future Sessions

* Always confirm PR naming convention adherence.

* Use `gh` CLI commands for GitHub operations.

* Check for Terraform deprecation warnings and migrate to dedicated resources.

* Confirm Terraform state is stored remotely before proceeding with applies.

---

## Epic E03: AWS Organization and Control Tower Governance Bootstrap

### Infrastructure & Governance Notes

* **Control Tower Manifest Limitations**:  The `aws_controltower_landing_zone` Terraform resource manifest strictly manages Landing Zone configuration such as governed regions and logging. It **does not support** managing Organizational Units (OUs) or Service Control Policies (SCPs).  OUs must be managed separately using native `aws_organizations_organizational_unit` Terraform resources.

* **Organizational Units (OUs)**:  Created and managed via `aws_organizations_organizational_unit` resources to define account boundaries and governance domains.

* **Service Principals for Control Tower**:  The AWS Organization must enable the service principal `member.org.stacksets.cloudformation.amazonaws.com` to support Control Tower Account Factory operations. This is a required addition to the `aws_organizations_organization` resource to avoid drift.

### Tooling & CI/CD Notes

* **Checkov Pre-commit Hook**:  The `terraform_checkov` hook from `antonbabenko/pre-commit-terraform` (v1.105.0) does **not** support passing a config file via `--config-file` argument in `args`.  The `.checkov.yml` configuration file must be placed in the repository root for automatic discovery by Checkov.

* **TFLint Hygiene**:  Maintain a zero-warning policy. Remove unused Terraform declarations such as `data "aws_caller_identity" "current"` immediately to keep CI signals clean and avoid noise.

* **Checkov Compliance**: Added `checkov:skip=CKV_AWS_274` for the `AdministratorAccess` policy attachment in `audit_role.tf` to acknowledge the requirement for full administrative permissions for the delegated security role.

* **TFLint**: Addressed unused variable warnings to maintain a clean CI signal.

### Lessons Learned

* Attempting to manage OUs via the Control Tower manifest results in API validation errors. Always use native AWS Organizations resources for OU management.

* The Control Tower Landing Zone resource requires precise manifest JSON matching the AWS API schema; deviations cause update failures.

## Recent Learnings and Cleanup (2026-03-09)

* Successfully cleaned up Terraform state to remove stuck resources causing errors.
* Reverted Terraform code to a stable baseline allowing clean `terraform apply`.
* Budgets (`budgets.tf`) are working and included in the clean apply.
* Documented the "Object Lock Trap" where S3 buckets with Compliance mode cannot be deleted or renamed by Terraform.
* Noted Control Tower's management of Organization Trail and its KMS key prevents direct modification via Terraform.
* GuardDuty delegation requires careful provider separation to avoid member account management errors.
* Current state is stable and ready for next stories.

---

* Pre-commit hooks can have subtle argument parsing issues; always verify hook documentation and test locally.

* Service principals required by AWS services like Control Tower must be explicitly declared in Terraform to prevent drift.

* Remote Terraform state backend configuration with S3 and DynamoDB locking is critical for multi-account deployments and must be verified after bootstrap.

* **Graph Checks**: Checkov `CKV2` checks require a full directory context (`-d`) to resolve relationships between resources (e.g., Org vs. Detector).

* **Hook Limitations**: The `terraform_checkov` pre-commit hook does not support the `--config-file` argument; it relies on auto-discovery of `.checkov.yml` in the root.

* **Delegated Admin Pattern**: In a multi-account setup, the Management account detector exists primarily to facilitate delegation; the actual Org configuration happens via the Delegated Admin provider.

* **Security Hub Delegation**: Once administration is delegated, the Management account can no longer manage organization-wide configuration. However, the Audit account (Delegated Admin) cannot manage standards _inside_ the Management account. A dual-provider approach is required in Terraform.

* **CloudTrail KMS**: CloudTrail Organization Trails can use a KMS key in the Management account to encrypt logs delivered to a bucket in a different account, provided the bucket and key policies are correctly aligned.

### Current Project State Update

* **Current Epic**: E03 (AWS Organization + Control Tower)

* **Current Story**: S011 (Log bucket immutability / Object Lock / retention guardrails)

* **Completed in E03**:

  * S001: Org Bootstrap + Remote State Import.

  * S002: Control Tower LZ v4.0 Import & Alignment.

  * S003: Core OU Structure (Security, Infrastructure, Workloads, Sandbox).

  * S004: Enable CloudTrail Organization Trail.

  * S005: Centralized CloudTrail Logging.

  * S006: AWS Config Aggregator.

  * S007: GuardDuty delegated administration.

  * S008: Security Hub and Finding Aggregator.

  * S009: Baseline SCPs (IAM user restrictions, security service protection, deny leave organization).

  * S010: Region restriction SCP for approved workload regions.

  * S013: Cost budgets and anomaly detection.

---

## Recent Learnings and Session Notes (2026-03-07)

* GuardDuty delegation successfully transferred to Log Archive account (172134854767).

* CloudTrail CloudWatch Logs integration blocked by persistent `InvalidCloudWatchLogsLogGroupArnException`.

* Identified that the AWSServiceRoleForCloudTrail SLR requires explicit KMS permissions.

* Workaround implemented: CloudTrail running in S3-only mode with CloudWatch Logs integration commented out.

* No SCPs or permission boundaries blocking the current setup.

* Terraform state updated to reflect current GuardDuty delegation.

* Pending: Open AWS Support case to resolve CloudTrail validation issue.

### Documented Exceptions

* **Checkov CKV2_AWS_10**: CloudTrail organization trail is currently running without CloudWatch Logs integration due to a persistent AWS validation error (`InvalidCloudWatchLogsLogGroupArnException`). This is a known limitation being tracked for future resolution once AWS validation issues are resolved.

## Recent Work Completed (2026-03-08)

* Successfully enabled GuardDuty delegated administrator account configuration using a dedicated provider alias for the Log Archive account.

* Corrected GuardDuty organization configuration resource to use the delegated admin's detector ID.

* Fixed CloudTrail CloudWatch Logs integration by explicitly including the ':\*' suffix in the log group ARN.

* Updated IAM role policy to match the explicit CloudWatch Logs ARN pattern.

* Verified successful Terraform apply with no errors.

This resolves the previous issues with GuardDuty delegation and CloudTrail logging integration.

---

## Session Update: 2026-03-08

### Infrastructure & Security Progress (Epic E03)

* **GuardDuty (S007)**: Successfully configured GuardDuty detectors in Management account (`us-east-1` and `us-west-2`).

* **Delegated Administration**: Established delegation to the Security/Log Archive account (`172134854767`).

* **Org Configuration**: Enabled organization-wide GuardDuty with S3, Kubernetes, and Malware protection data sources auto-enabled for all members.

* **Finding Frequency**: Updated `finding_publishing_frequency` to `FIFTEEN_MINUTES` to meet security best practices and resolve `CKV2_AWS_3`.

* **Security Hub (S008)**:

  * Successfully enabled Security Hub and delegated administration to the Audit account (`881413600100`).

  * Enabled "AWS Foundational Security Best Practices" and "CIS AWS Foundations Benchmark" standards.

  * **Finding Aggregator**: Configured organization-wide finding aggregation in the Audit account with `linking_mode = "ALL_REGIONS"`.

  * **Provider Architecture**: Implemented a provider-split model where the Management account manages its own standards while the Audit account manages organization-wide configuration.

* **CloudTrail (S004)**:

  * Verified Organization Trail is correctly logging to the centralized S3 bucket in the Log Archive account.

  * Confirmed KMS encryption using the Management account CMK is functional and delivery is successful.

### Tooling & CI/CD Alignment

* **Checkov Consistency**: Aligned local `pre-commit` with GitHub Actions by forcing `--directory=infra/` and `--framework=terraform` in `.pre-commit-config.yaml`.

* **Checkov Configuration**: Confirmed `.checkov.yml` in the root is the "Single Source of Truth" for both local and CI scans.

* **Policy Suppression**: Applied `checkov:skip=CKV2_AWS_3` to Management account detectors with clear documentation, acknowledging the delegated administration model.

* **Credential Management**: Resolved `ExpiredToken` errors by refreshing AWS SSO/STS sessions for the `infra-lab` profile.

### Session Update: 2026-03-22

* **Epic E03 / Story S010**: Configure IAM Identity Center.

---

## Session Update: 2026-03-21

### Infrastructure & Governance Progress (Epic E03)

* **SCPs (S009)**: Successfully implemented and applied hardened Service Control Policies across the organization.

* **IAM User Prevention**: Expanded the IAM-user-deny SCP to block creation and management of IAM users, login profiles, access keys, signing certificates, and service-specific credentials to reinforce IAM Identity Center adoption.

* **Security Service Protection**: Replaced the earlier security-protection SCP with a more granular policy that denies mutation or disabling of CloudTrail, AWS Config, and GuardDuty.

* **Organization Retention**: Replaced the prior leave-organization SCP with a standardized, tagged policy preventing member accounts from leaving the AWS Organization.

* **Administrative Exemptions / Break-Glass**: Added `ArnNotLike` exemptions for `AWSControlTowerExecution`, `AWSCloudFormationStackSetExecutionRole`, and `OrganizationAccountAccessRole` so automation and break-glass administration remain functional.

* **Attachment Strategy**: Applied the leave-organization SCP at the Organization Root and applied the security-protection SCP to the Security, Infrastructure, and Workloads OUs. Updated the existing IAM-user SCP in place.

* **Control Tower Centralized Logging**: Successfully updated the Control Tower Landing Zone manifest to enable `centralizedLogging` targeting the Log Archive account (`172134854767`) after correcting manifest schema/type issues.

### Lessons Learned (2026-03-21)

* **Control Tower Manifest Types**: `retentionDays` values in the Landing Zone manifest must be integers, not strings, or the Control Tower API returns a schema `ValidationException`.

* **GuardDuty Delegation Constraint**: After delegation is enabled, the Management account cannot update delegated GuardDuty detector properties such as `finding_publishing_frequency`; Terraform must stop managing those mutable fields from the Management account context.

* **Provider Auth Pattern**: The `audit` provider must use the Management account profile (`infra-lab`) as the source for `assume_role` into `OrganizationAccountAccessRole`; attempting to assume that role from an Audit-account SSO session results in `AccessDenied`.

* **SCP Safety Model**: Verified that SCPs do not apply to the Management account and that break-glass access remains available through `OrganizationAccountAccessRole`, reducing lockout risk.

* **Long-Running Apply Behavior**: Control Tower Landing Zone updates can legitimately take ~24 minutes through Terraform; extended `Still modifying...` output is normal.
* Completed **E03-S009** by finalizing baseline SCP coverage for IAM user restrictions, protection of core security services, and denial of `organizations:LeaveOrganization`.

* Completed **E03-S010** by implementing and attaching a region restriction SCP for the `Workloads` OU, limited to approved regions `us-east-1` and `us-west-2`.

* Added a lockout-safe SCP exemption for IAM Identity Center administrator sessions using the role pattern `arn:aws:iam::*:role/AWSReservedSSO_AWSAdministratorAccess_*` after verifying the active admin path with `aws sts get-caller-identity --profile infra-lab`.

* Completed the missing sandbox attachment for the security-protection SCP.

* Normalized Control Tower landing zone manifest retention values from strings to integers to eliminate repeated `manifest_json` drift and unnecessary long-running landing zone updates.

### Next Steps

* **Epic E03 / Story S011**: Log bucket immutability / Object Lock / retention guardrails.

* **Epic E04**: Continue with IAM Identity Center / shared services follow-on work already started outside the strict E03 order.

## Session Update: 2026-03-22 (Foundation Validation Harness)

### Validation Harness Delivered

* Added a single Python validation script: `scripts/validate_foundation.py`.

* Purpose: provide a repo-specific validation harness for all completed work from E01 through E03-S010.

* The script validates:
  * **E01**: repository structure, SDLC scaffolding, GitHub workflow presence, pre-commit baseline.
  * **E02**: Terraform layout, module interface completeness, formatting, validate, local pre-commit execution, remote state backend controls.
  * **E03**: AWS Organization, Control Tower, OU structure, CloudTrail, Config aggregator, GuardDuty, Security Hub, budgets/anomaly detection, and SCP attachments.

* The validator now includes visible progress output for long-running stages so execution does not appear hung.

* The validator was refined to be repo-specific for `infra-lab`:
  * `infra/live/shared` is the active live root currently validated.
  * Terraform roots validated:
    * `infra/mgmt/backend`
    * `infra/mgmt/org`
    * `infra/live/shared`
  * Module interface checks aligned to the actual modules present in `infra/modules`.

### Linting / Quality Notes

* Added Python linting awareness to local workflow and validated the script against strict `flake8` settings.

* Resolved `flake8` issues including:
  * line length (`E501`)
  * docstring requirements (`D101`, `D102`, `D103`, `D400`, `D401`)

* Confirmed `pre-commit run --all-files` passes locally after updates.

### Validation Baseline Outcome

* Final validator result:
  * **Total Checks**: 73
  * **Pass**: 68
  * **Warn**: 5
  * **Fail**: 0

* Known warnings remaining are expected / acceptable:
  * changelog or release drafter scaffold not yet created
  * `docs/adr` scaffold not yet created
  * docs site scaffold not yet created
  * terraform-docs config not yet present
  * Control Tower-managed CloudTrail KMS key visibility limitation

### Security Hub Validation Lesson Learned

* `aws_securityhub_finding_aggregator` was already correctly deployed in Terraform in `infra/mgmt/org/securityhub_standards.tf` using the delegated admin (`aws.audit`) provider.

* Initial validator result was a false negative because Security Hub checks were performed only with the Management account profile.

* Correct validation model for Security Hub:
  * **Management profile (`infra-lab`)** for `list-organization-admin-accounts`
  * **Audit profile (`infra-lab-security-audit`)** for:
    * `get-enabled-standards`
    * `list-finding-aggregators`

* This split-profile validation accurately reflects the delegated admin architecture.

### SDLC Hardening Added During This Session

* Added root `LICENSE`.

* Added `.github/ISSUE_TEMPLATE/` scaffolding.

* Added `.github/pull_request_template.md`.

* Added `.github/dependabot.yml`.

* Fixed markdownlint issues in `.github/pull_request_template.md`.

* Identified and corrected a Markdown table alignment issue in `infra/modules/s3_secure_bucket/README.md` to satisfy `markdownlint` rule `MD060`.

### Carry-Forward Notes

* Preserve `scripts/validate_foundation.py` as a reusable baseline contract test for future epics.

* Future changes to org/security architecture should update the validator in parallel to keep the contract current.

* Do not remove historical notes from this document without explicit approval.

* **Control Tower Log Buckets & Object Lock**:
  Control Tower-managed S3 log buckets do not have Object Lock enabled and cannot be retrofitted with Object Lock after creation. Log immutability must be achieved via:
  * versioning
  * lifecycle retention policies
  * SCP-based delete protections

  This is an intentional architectural constraint. Object Lock would require a greenfield bucket and is not compatible with Control Tower-managed logging.
