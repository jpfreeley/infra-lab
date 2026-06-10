# ADR-004: Standardized Module Interface

## Status

Accepted

## Context

Reusable Terraform modules need consistent interfaces so callers know what to
expect and code reviews are predictable.

## Decision

Every module must have:

- `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Standard variables: `project` (default "infra-lab"), `tags` (map(string))
- All resources tagged via `merge(var.tags, { Name, ManagedBy, Project })`
- Version constraint: `>= 1.7.0` Terraform, `>= 5.0` AWS provider

## Consequences

- Consistent discovery — any module has the same file structure
- Tags propagate uniformly for cost allocation and compliance
- New modules are quick to create from the pattern
- Slightly verbose (every module repeats the same boilerplate)
