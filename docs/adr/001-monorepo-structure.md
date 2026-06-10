# ADR-001: Monorepo with Clear Boundaries

## Status

Accepted

## Context

The platform needs a repository structure that supports Terraform infrastructure,
application code, and documentation in a single repository while maintaining clear
ownership and review boundaries.

## Decision

Use a monorepo with three top-level directories:

- `/infra` — Terraform modules and live environments
- `/app` — Application source code
- `/docs` — Documentation, runbooks, build journals

CODEOWNERS enforces review requirements per directory.

## Consequences

- Single repo simplifies CI/CD, versioning, and cross-cutting changes
- Clear boundaries prevent app code from leaking into infra and vice versa
- CODEOWNERS ensures infrastructure changes get platform team review
- Trade-off: larger repo size over time (mitigated by sparse checkout if needed)
