# Prod Environment VPCs
# Epic: E05 - Networking (Dual VPC per env)
# Stories: S008 (Control VPC), S009 (Execution VPC), S024 (NAT per-AZ)

###############################################################################
# Control VPC - Management/Orchestration
###############################################################################

module "control_vpc" {
  source = "../../modules/vpc"

  name       = "${local.name_prefix}-control"
  cidr_block = local.control_vpc_cidr

  enable_internet_gateway = true
  nat_gateway_count       = 0 # No NAT — cost optimization until workloads deployed

  public_subnets  = local.control_public_subnets
  private_subnets = local.control_private_subnets
  data_subnets    = local.control_data_subnets

  # Peering to Execution VPC
  peer_vpc_id   = module.execution_vpc.vpc_id
  peer_vpc_cidr = local.execution_vpc_cidr

  # Flow logs disabled — cost optimization until workloads deployed
  enable_flow_logs = false

  tags = local.common_tags
}

###############################################################################
# Execution VPC - Tenant/Worker Workloads
###############################################################################

module "execution_vpc" {
  source = "../../modules/vpc"

  name       = "${local.name_prefix}-execution"
  cidr_block = local.execution_vpc_cidr

  enable_internet_gateway = true
  nat_gateway_count       = 0 # No NAT — cost optimization until workloads deployed

  public_subnets  = local.execution_public_subnets
  private_subnets = local.execution_private_subnets
  data_subnets    = local.execution_data_subnets

  # Flow logs disabled — cost optimization until workloads deployed
  enable_flow_logs = false

  tags = local.common_tags
}

###############################################################################
# Peering route: Execution → Control
###############################################################################

resource "aws_route" "execution_private_to_control" {
  count = length(module.execution_vpc.private_route_table_ids)

  route_table_id            = module.execution_vpc.private_route_table_ids[count.index]
  destination_cidr_block    = local.control_vpc_cidr
  vpc_peering_connection_id = module.control_vpc.peering_connection_id
}

resource "aws_route" "execution_data_to_control" {
  count = module.execution_vpc.data_route_table_id != null ? 1 : 0

  route_table_id            = module.execution_vpc.data_route_table_id
  destination_cidr_block    = local.control_vpc_cidr
  vpc_peering_connection_id = module.control_vpc.peering_connection_id
}
