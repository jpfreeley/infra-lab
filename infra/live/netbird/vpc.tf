# NetBird VPC
# ADR-037: public-only, no NAT Gateway. The task gets a public IP for
# outbound pulls; its security group accepts TCP only from the NLB's SG.

module "netbird_vpc" {
  source = "../../modules/vpc"

  name       = "${local.name_prefix}-vpc"
  cidr_block = local.vpc_cidr

  enable_internet_gateway = true
  nat_gateway_count       = 0

  public_subnets = local.public_subnets

  enable_flow_logs = false # Cost optimization, same as the MemPalace VPC

  tags = local.common_tags
}
