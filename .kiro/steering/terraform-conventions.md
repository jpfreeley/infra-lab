# Terraform Conventions (infra-lab)

## Module Interface Patterns

- Every module must have: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Standard variables across all modules: `project` (default: "infra-lab"), `tags` (map(string))
- Use `var.tags` merged with resource-specific tags in every resource
- Terraform version constraint: `>= 1.7.0`, AWS provider: `>= 5.0`

## Live Environment Structure

- Each environment root (`infra/live/{env}/`) must have:
  - `providers.tf` — terraform block + provider config
  - `variables.tf` — input variables (`aws_region`, `aws_profile`, `environment`)
  - `locals.tf` — derived values (`name_prefix`, `environment`, `common_tags`)
  - Domain-specific `.tf` files (vpc.tf, ecs.tf, etc.)
- Use `var.environment` in locals — never hardcode the environment string
- `.tfvars` files are gitignored; defaults go in `variables.tf`

## Pre-commit / Linting

- All pre-commit hooks must pass before committing: trailing-whitespace, end-of-file-fixer, check-yaml, terraform_fmt, terraform_tflint, terraform_validate, terraform_checkov, terraform_docs, gitleaks
- **tflint zero-warning policy**: No unused variables, locals, or data sources. Remove them immediately or use them.
- `terraform validate` requires `terraform init -backend=false` in each root first
- Use `TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache` when initializing multiple roots to save disk and time

## Checkov Conventions

- Inline skip annotations must include a rationale: `# checkov:skip=CKV_XXX: "reason"`
- Common dev-environment skips (must be enforced in prod):
  - `CKV_AWS_158` — CloudWatch KMS encryption (optional in dev)
  - `CKV_AWS_338` — 365-day log retention (shorter ok in dev)
  - `CKV_AWS_150` — ALB deletion protection (disabled in dev)
  - `CKV_AWS_91` — ALB access logs (disabled in dev for cost)
  - `CKV_AWS_224` — ECS exec logging CMK (optional in dev)
- **CKV2_AWS_12**: Every VPC module must include `aws_default_security_group` with no ingress/egress rules to restrict the default SG
- Graph checks (`CKV2_*`) need full directory context (`checkov -d infra/`) to resolve cross-resource relationships

## Markdown Linting (CI + Local)

- CI uses `markdownlint-cli2-action` which enforces MD060 (table column style)
- Local pre-commit also runs `markdownlint-cli2` via `npx` on all `.md` files (parity with CI)
- Table separator rows must have spaces: `| --- | --- |` not `|---|---|`
- Ordered lists use `1.` for all items (MD029, style: 1/1/1)
- MD013 (line length) is disabled in `.markdownlint-cli2.yaml`
- MD032: Lists must have blank lines before and after
- MD012: No multiple consecutive blank lines
- MD024: No duplicate heading content (rename with context if needed)

## Security Group Module

- Variable name is `ingress` (list of objects), NOT `ingress_rules`
- Each object: `{ description, from_port, to_port, protocol, cidr_blocks?, security_groups?, self? }`
