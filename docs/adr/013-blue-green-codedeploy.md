# ADR-013: Blue/Green Deployment via CodeDeploy

## Status

Accepted

## Context

API service deployments need to be safe, fast, and rollback-capable.
Options: rolling update, blue/green, canary.

## Decision

API service uses CodeDeploy with ECS blue/green deployment:

- Canary strategy: 10% traffic for 5 minutes, then full shift
- Automatic rollback on deployment failure
- Test listener for pre-production validation
- Production traffic on port 443, test on port 8443

Workers use rolling deployment (simpler, no traffic shifting needed).

## Consequences

- Zero-downtime deployments for the API
- Instant rollback to previous version if health checks fail
- Test listener allows validation before promoting to production
- More complex infrastructure (2 target groups, CodeDeploy app + deployment group)
- Workers don't need this complexity (no external traffic)
