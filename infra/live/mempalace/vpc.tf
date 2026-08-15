# MemPalace VPC
# ADR-034: public-only, no NAT Gateway — same cost lever ADR-031 used for
# the WorkSpaces account. The ECS task gets a public IP directly; its
# security group (in mempalace.tf) only accepts ingress from the ALB's SG,
# so the public IP alone doesn't expose the task port.

module "mempalace_vpc" {
  source = "../../modules/vpc"

  name       = "${local.name_prefix}-vpc"
  cidr_block = local.vpc_cidr

  enable_internet_gateway = true
  nat_gateway_count       = 0

  public_subnets = local.public_subnets

  enable_flow_logs = false # Cost optimization — enable when needed

  tags = local.common_tags
}
