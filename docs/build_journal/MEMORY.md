
# MEMORY.md

## User Profile & Preferences
- **Shell**: `zsh`
- **Package Manager**: Homebrew (`brew`)
- **Security Conscious**: Prefers official, corporate tooling from reputable sources only.
- **Workflow Preference**: Uses GitHub CLI (`gh`) for all repo and PR operations.
- **Security Stance**: Prefers strong encryption (KMS CMKs) and no random 3rd party tools.

## Local Environment & Tooling
- **gh** (GitHub CLI): Primary tool for repo/PR management.
- **terraform**: Infrastructure as Code engine (v1.7.0+).
- **pre-commit**: Framework for managing git hooks.
- **tflint**: Terraform linter.
- **checkov**: Static analysis for IaC security.
- **gitleaks**: Secret detection (Note: uses local hook due to macOS dyld compatibility).
- **aws-cli**: AWS command line interface.

## AWS Environment Context
- **Organization Management Account ID**: `551452024305`
- **AWS Profile Name**: `infra-lab` (Primary profile for Terraform admin operations).
- **Primary Region**: `us-east-1` (N. Virginia).
- **Replica Region**: `us-west-2` (Oregon).

### AWS Caller Identity (`--profile infra-lab`)
```json
{
    "UserId": "USERID",
    "Account": "551452024305",
    "Arn": "arn:aws:iam::551452024305:user/terraform-admin"
}
```

## Project Backlog
- **Master Backlog File**: `backlog_granular.json`
- **Backlog URL**: [http://ypgmedia.com/infra_lab/backlog_granular.json](http://ypgmedia.com/infra_lab/backlog_granular.json)
- **Source of Truth**: This file contains the full list of Epics and Stories used to drive the project.
- **Current Epic**: E02
- **Current Story**: S003

## Repository & Workflow
- **Repository Name**: `infra-lab` (Private).
- **Monorepo Structure**: Clear boundaries: `/infra`, `/app`, `/docs`.
- **Governance**: Enforced PR-first workflow with GitHub branch protection and CODEOWNERS.
- **PR Naming Convention**: `[jpf] [<Exx-Sxxx>] <Description>`
  - `<Exx-Sxxx>` = Epic and Story number, e.g., `E01-S001`.
  - `<Description>` = Self-explanatory summary.

## Infrastructure & Security
- **Encryption**: Uses customer-managed KMS keys for S3 and DynamoDB with rotation.
- **Backend Storage**: S3 bucket `infra-lab-tf-state-551452024305`.
- **State Locking**: DynamoDB table `infra-lab-tf-state-locks`.
- **High Availability**: Cross-region replication enabled (Primary: `us-east-1`, Replica: `us-west-2`).
- **S3 Hardening**: All buckets have public access blocks and ownership controls enabled.
- **Validation**: Pre-commit hooks integrated (Terraform fmt, lint, Checkov, Gitleaks).

## Terraform & AWS Usage
- **State Management**: Successfully migrated from local to remote S3 backend.
- **Provider Standards**: Uses AWS provider (v5.x) with dedicated resources for lifecycle, versioning, and encryption.
- **Resource Handling**: AWS Organizations resource is imported if already existing.

## Notes for Future Sessions
- Always confirm PR naming convention adherence.
- Use `gh` CLI commands for GitHub operations.
- Check for Terraform deprecation warnings and migrate to dedicated resources.
- Confirm Terraform state is stored remotely before proceeding with applies.

## Local Environment & Tooling (Updated 2026-03-06)
- **Local Repo Path**: `/Users/freeleyj/Documents/git/public/jpfreeley/infra-lab`
- **Download Path**: `/Users/freeleyj/Downloads`
- **Workflow Note**: Files generated in chat are moved from Downloads to the local repo path using `mv`.

## Project Progress
- **Current Epic**: E02
- **Current Story**: S004
- **Completed Stories**:
  - E01-S001 to E01-S002: Repo skeleton and pre-commit hooks.
  - E02-S001 to E02-S002: Root layout and remote state backend.
  - E02-S003: Multi-account provider + AssumeRole strategy (Merged).

## Infrastructure & Security (Updated)
- **Provider Pattern**: Standardized `providers.tf` using `assume_role` for target accounts.
- **Modules**:
  - `kms_key`: Reusable module with enforced rotation and alias validation.
