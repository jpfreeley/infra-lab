# ADR-030: Compute Layer Off by Default in Dev

## Status

Accepted

## Context

The dev environment's compute layer (ALB + API task) costs ~$31/mo even when idle.
For a lab environment that's used intermittently, this is waste.

Workers are already scale-from-zero (ADR-015). The remaining always-on resources
are the ALB ($16/mo hourly charge) and a single API task ($15/mo).

## Decision

Make the entire compute layer off by default in dev:

- **API service**: `desired_count = 0`, `min_capacity = 0` (scale-from-zero like workers)
- **ALB**: Conditional via `var.enable_alb = false` (not deployed by default)
- **CodeDeploy**: Conditional, same as ALB (only needed when ALB exists)

To bring everything up for development/testing:

```bash
# Enable ALB (requires terraform apply)
terraform apply -var="enable_alb=true"

# Scale API to 1+ tasks (immediate, no apply needed)
aws ecs update-service --cluster infra-lab-dev-control \
  --service infra-lab-dev-api --desired-count 1 --profile infra-lab
```

## Consequences

- Dev compute idle cost reduced from ~$31/mo to $0/mo
- Total platform idle: ~$17-20/mo (governance + KMS keys only)
- ALB requires `terraform apply` to create/destroy (not instant toggle)
- API task can be scaled instantly via CLI (lifecycle ignores desired_count)
- No external API endpoint available until ALB is enabled
- Blue/green deployment not available without ALB
