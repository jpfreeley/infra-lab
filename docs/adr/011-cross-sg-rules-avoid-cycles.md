# ADR-011: Cross-SG Rules to Avoid Dependency Cycles

## Status

Accepted

## Context

Security groups that reference each other (ALB → ECS → RDS) create Terraform
dependency cycles when defined inline within the security group resource.

## Decision

Use `aws_security_group_rule` resources for cross-SG references instead of
inline `ingress`/`egress` blocks with `security_groups` lists.

Security group modules define base rules only. Cross-references are added
as standalone rule resources in the calling environment.

## Consequences

- No dependency cycles in Terraform plan
- Security groups can be created in any order
- More verbose (separate rule resources) but explicit and debuggable
- Changes to cross-SG rules don't force replacement of the entire SG
