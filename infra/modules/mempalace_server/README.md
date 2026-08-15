# MemPalace Server Module

Deploys MemPalace's own documented [Remote/Team Server mode](https://github.com/MemPalace/mempalace)
on ECS Fargate: `qdrant` (internal-only, task-local) + `mempalace serve`
(bearer-token auth, the container the ALB targets). See
[ADR-034](../../../docs/adr/034-shared-mempalace-server.md) for the full
design rationale.

Deliberately portable — every input is a variable, nothing is hardcoded to
infra-lab's account IDs, domain, or org structure. This module owns compute
and storage for the app itself; it does not create a VPC, ALB, WAF, ACM
certificate, or the bearer token's value. Bring your own.

## Scope boundary

| Owned by this module | Owned by the caller |
| --- | --- |
| ECS task definition (2 containers) | VPC / subnets |
| ECS service | ALB / target group / listener |
| EFS filesystem + access points | WAF |
| Security groups for the task and EFS | ACM certificate |
| IAM execution + task roles | Secrets Manager secret **and its value** |
| CloudWatch log group | ECS cluster |

## Auth and secrets

This module takes a Secrets Manager ARN (`bearer_token_secret_arn`) and
never touches the secret's value — it only grants the execution role
`secretsmanager:GetSecretValue` on that one ARN. Generate the token
out-of-band and write it directly to the secret:

```bash
openssl rand -base64 32 | aws secretsmanager put-secret-value \
  --secret-id <secret-name> --secret-string file:///dev/stdin
```

Never pass the token as a Terraform variable, `.tfvars` value, or module
default — it would land in state and (for a `.tfvars` file) risk landing in
git.

## Usage

```hcl
module "mempalace" {
  source = "../../modules/mempalace_server"

  name                   = "mempalace"
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.public_subnet_ids
  alb_security_group_id  = module.sg_alb.id
  cluster_arn            = module.ecs_cluster.arn
  cluster_name           = module.ecs_cluster.name
  target_group_arn       = aws_lb_target_group.mempalace.arn
  bearer_token_secret_arn = module.mempalace_token.secret_arn
  kms_key_arn            = module.mempalace_kms.key_arn

  # Start small, right-size from real CloudWatch metrics (ADR-034)
  cpu    = 256
  memory = 512

  tags = local.common_tags
}
```

## Sizing

Defaults (`cpu = 256`, `memory = 512`) are a deliberate starting guess, not
a measured number — MemPalace's embedding step runs CPU-only in-container
and no memory footprint has been benchmarked yet. Deploy at the default,
watch real CloudWatch Container Insights metrics, and adjust — don't
pre-optimize this before there's data.

## Singleton service

One Qdrant + one mempalace share one EFS-backed dataset. `desired_count` is
capped at 1 by variable validation — this module does not support
horizontal scaling as designed.
