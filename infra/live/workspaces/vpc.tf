# WorkSpaces VPC
# Epic: E13 - AWS WorkSpaces Account
# Story: E13-S003 - Create WorkSpaces VPC with public/private subnets

###############################################################################
# WorkSpaces VPC
###############################################################################

module "workspaces_vpc" {
  source = "../../modules/vpc"

  name       = "${local.name_prefix}-vpc"
  cidr_block = local.vpc_cidr

  enable_internet_gateway = true
  nat_gateway_count       = var.enable_nat ? 1 : 0

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_flow_logs = false # Cost optimization for lab — enable when needed

  tags = local.common_tags
}

###############################################################################
# Data Sources
###############################################################################

data "aws_caller_identity" "current" {}
