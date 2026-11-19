# NetBird Account Locals
# ADR-037: Self-Hosted NetBird Server in a Dedicated Account, Torn Down When Idle

locals {
  project     = "infra-lab"
  environment = var.environment
  name_prefix = "${local.project}-${local.environment}"

  # Allocated in docs/networking-cidr-plan.md (next /20 after MemPalace).
  vpc_cidr = "10.0.128.0/20"

  # Public-only, no NAT Gateway (ADR-037, same cost pattern as ADR-031 and
  # ADR-034). Two AZs for EFS mount target redundancy and NLB nodes; the
  # ECS service itself is a singleton.
  public_subnets = [
    { cidr = "10.0.128.0/24", az = "us-east-1a" },
    { cidr = "10.0.129.0/24", az = "us-east-1b" },
  ]

  embedded_stun = length(var.stun_servers) == 0

  common_tags = {
    Environment = local.environment
    Service     = "netbird"
  }
}
