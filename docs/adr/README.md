# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the infra-lab platform.

## Format

Each ADR follows a lightweight format:

- **Status**: Accepted, Superseded, or Deprecated
- **Context**: Why the decision was needed
- **Decision**: What was decided
- **Consequences**: What happens as a result

## Index

| ADR | Title | Status | Epic |
| --- | --- | --- | --- |
| [001](001-monorepo-structure.md) | Monorepo with clear boundaries | Accepted | E01 |
| [002](002-remote-state-s3-dynamodb.md) | Remote state with S3 + DynamoDB | Accepted | E02 |
| [003](003-multi-account-provider-strategy.md) | Multi-account provider + AssumeRole | Accepted | E02 |
| [004](004-reusable-module-interface.md) | Standardized module interface | Accepted | E02 |
| [005](005-control-tower-landing-zone.md) | Control Tower for governance baseline | Accepted | E03 |
| [006](006-scp-enforcement-model.md) | SCP enforcement with break-glass exemptions | Accepted | E03 |
| [007](007-delegated-admin-pattern.md) | Delegated admin for security services | Accepted | E03 |
| [008](008-iam-identity-center-sso.md) | IAM Identity Center for all human access | Accepted | E04 |
| [009](009-github-oidc-keyless-cicd.md) | GitHub OIDC for keyless CI/CD | Accepted | E04 |
| [010](010-dual-vpc-per-environment.md) | Dual VPC per environment (control + execution) | Accepted | E05 |
| [011](011-cross-sg-rules-avoid-cycles.md) | Cross-SG rules to avoid dependency cycles | Accepted | E05 |
| [012](012-ecs-fargate-dual-cluster.md) | ECS Fargate with dual cluster model | Accepted | E06 |
| [013](013-blue-green-codedeploy.md) | Blue/green deployment via CodeDeploy | Accepted | E06 |
| [014](014-worker-tier-separation.md) | Worker tiers with independent scaling | Accepted | E06 |
| [015](015-scale-from-zero-dev.md) | Scale-from-zero in dev for cost optimization | Accepted | E06 |
| [016](016-aurora-serverless-v2.md) | Aurora Serverless v2 over provisioned | Accepted | E07 |
| [017](017-rds-proxy-mandatory.md) | RDS Proxy mandatory for ECS workloads | Accepted | E07 |
| [018](018-separate-clusters-per-plane.md) | Separate DB clusters per plane | Accepted | E07 |
| [019](019-rds-managed-secrets.md) | RDS-managed master passwords | Accepted | E07 |
| [020](020-queue-per-worker-tier.md) | Queue per worker tier | Accepted | E08 |
| [021](021-step-functions-orchestration.md) | Step Functions for job orchestration | Accepted | E08 |
| [022](022-fifo-dedup-for-ordered-work.md) | FIFO queue with content-based dedup | Accepted | E08 |
| [023](023-secrets-manager-over-ssm.md) | Secrets Manager for application secrets | Accepted | E09 |
| [024](024-private-ca-deferred.md) | Private CA deferred (cost) | Accepted | E09 |
| [025](025-cloudwatch-native-observability.md) | CloudWatch-native observability over OTel | Accepted | E10 |
| [026](026-tag-based-cost-allocation.md) | Tag-based cost allocation | Accepted | E11 |
| [027](027-tag-based-backup-selection.md) | Tag-based backup selection | Accepted | E12 |
| [028](028-pre-commit-ci-parity.md) | Pre-commit local/CI parity | Accepted | E01 |
| [029](029-rds-auto-stop-mechanism.md) | RDS auto-stop via EventBridge + Lambda | Accepted | E07 |
| [030](030-compute-off-by-default.md) | Compute layer off by default in dev | Accepted | E06 |
