# ADR-010: Dual VPC per Environment (Control + Execution)

## Status

Accepted

## Context

The platform has two planes: control (API, orchestration) and execution (workers,
tenant workloads). These have different security profiles and scaling characteristics.

## Decision

Each environment gets two VPCs:

- **Control VPC**: API services, ALB, management workloads
- **Execution VPC**: Worker services, restricted egress, tenant isolation

VPCs are peered for controlled cross-plane communication.

## Consequences

- Strong network isolation between control and execution planes
- Independent scaling of network resources per plane
- NACLs can restrict execution plane egress (defense in depth)
- VPC peering adds complexity but enables PrivateLink patterns
- More subnets and route tables to manage (mitigated by VPC module)
