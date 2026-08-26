# MemPalace Account Locals
# ADR-034: Shared MemPalace Server as a Portable App on Dedicated Infra

locals {
  project     = "infra-lab"
  environment = var.environment
  name_prefix = "${local.project}-${local.environment}"

  # Shorter prefix for the MagNet Legal instance's own resources —
  # "${local.name_prefix}-magnetlegal-tg" (34 chars) exceeds the ALB
  # target group name limit (32 chars). Drops the redundant "mempalace"
  # (already implied by being in this live directory) rather than
  # abbreviating "magnetlegal", which needs to stay recognizable.
  magnetlegal_prefix = "${local.project}-magnetlegal"

  # MemPalace VPC — allocated from the "reserved / future" block in
  # docs/networking-cidr-plan.md (10.0.112.0/20)
  vpc_cidr = "10.0.112.0/20"

  # Public-only, no NAT Gateway (ADR-034/ADR-031 cost pattern). Two AZs for
  # EFS mount target redundancy; the ECS service itself is a singleton
  # (desired_count capped at 1 by the module).
  public_subnets = [
    { cidr = "10.0.112.0/24", az = "us-east-1a" },
    { cidr = "10.0.113.0/24", az = "us-east-1b" },
  ]

  common_tags = {
    Environment = local.environment
    Service     = "mempalace"
  }
}
