
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
    "UserId": "USERID",
    "Account": "551452024305",
    "Arn": "arn:aws:iam::551452024305:user/terraform-admin"
}
```

## Project Backlog

* **Master Backlog File**: `backlog_granular.json`

* **Backlog URL**: [http://ypgmedia.com/infra_lab/backlog_granular.json](http://ypgmedia.com/infra_lab/backlog_granular.json)

* **Source of Truth**: This file contains the full list of Epics and Stories used to drive the project.

* **Current Epic**: E02

* **Current Story**: S003

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

* **Control Tower Manifest Limitations**:
  The `aws_controltower_landing_zone` Terraform resource manifest strictly manages Landing Zone configuration such as governed regions and logging. It **does not support** managing Organizational Units (OUs) or Service Control Policies (SCPs).
  OUs must be managed separately using native `aws_organizations_organizational_unit` Terraform resources.

* **Organizational Units (OUs)**:
  Created and managed via `aws_organizations_organizational_unit` resources to define account boundaries and governance domains.

* **Service Principals for Control Tower**:
  The AWS Organization must enable the service principal `member.org.stacksets.cloudformation.amazonaws.com` to support Control Tower Account Factory operations. This is a required addition to the `aws_organizations_organization` resource to avoid drift.

### Tooling & CI/CD Notes

* **Checkov Pre-commit Hook**:
  The `terraform_checkov` hook from `antonbabenko/pre-commit-terraform` (v1.105.0) does **not** support passing a config file via `--config-file` argument in `args`.
  The `.checkov.yml` configuration file must be placed in the repository root for automatic discovery by Checkov.

* **TFLint Hygiene**:
  Maintain a zero-warning policy. Remove unused Terraform declarations such as `data "aws_caller_identity" "current"` immediately to keep CI signals clean and avoid noise.

### Lessons Learned

* Attempting to manage OUs via the Control Tower manifest results in API validation errors. Always use native AWS Organizations resources for OU management.
* The Control Tower Landing Zone resource requires precise manifest JSON matching the AWS API schema; deviations cause update failures.
* Pre-commit hooks can have subtle argument parsing issues; always verify hook documentation and test locally.
* Service principals required by AWS services like Control Tower must be explicitly declared in Terraform to prevent drift.
* Remote Terraform state backend configuration with S3 and DynamoDB locking is critical for multi-account deployments and must be verified after bootstrap.

### Current Project State Update

* **Current Epic**: E03 (AWS Organization + Control Tower)
* **Current Story**: S004 (Enable CloudTrail Organization Trail)
* **Completed in E03**:
  * S001: Org Bootstrap + Remote State Import.
  * S002: Control Tower LZ v4.0 Import & Alignment.
  * S003: Core OU Structure (Security, Infrastructure, Workloads, Sandbox).

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
