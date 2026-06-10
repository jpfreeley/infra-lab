# ADR-028: Pre-Commit Local/CI Parity

## Status

Accepted

## Context

Developers run pre-commit hooks locally before pushing. GitHub CI runs
its own checks. If these differ, code passes locally but fails in CI
(or vice versa), causing confusion and wasted cycles.

## Decision

Pre-commit hooks must mirror CI checks exactly:

- terraform_fmt → Terraform CI fmt check
- terraform_tflint → Terraform CI tflint
- terraform_validate → Terraform CI validate
- terraform_checkov → Terraform CI checkov
- markdownlint (npx markdownlint-cli2) → Docs CI markdownlint-cli2-action
- gitleaks → Secret Scanning workflow

When adding a CI check, always add the equivalent to `.pre-commit-config.yaml`.

## Consequences

- Local failures predict CI failures accurately
- No surprises after pushing (what passes locally passes in CI)
- Must keep pre-commit hooks and CI workflows in sync
- Checkov version differences between local and CI can still cause edge cases
  (CKV2 graph checks may behave differently across versions)
