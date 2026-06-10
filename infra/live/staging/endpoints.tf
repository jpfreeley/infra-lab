# VPC Endpoints
# Epic: E05 - Networking (Dual VPC per env)
#
# NOTE: Interface endpoints disabled for cost optimization.
# Only free S3 Gateway endpoints are active.

###############################################################################
# S3 Gateway Endpoint (Control VPC) - FREE
###############################################################################

module "endpoint_s3_control" {
  source = "../../modules/vpc_endpoint"

  vpc_id        = module.control_vpc.vpc_id
  service_name  = "com.amazonaws.us-east-1.s3"
  endpoint_type = "Gateway"

  route_table_ids = concat(
    module.control_vpc.private_route_table_ids,
    compact([module.control_vpc.data_route_table_id])
  )

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-control-s3-endpoint"
  })
}

###############################################################################
# S3 Gateway Endpoint (Execution VPC) - FREE
###############################################################################

module "endpoint_s3_execution" {
  source = "../../modules/vpc_endpoint"

  vpc_id        = module.execution_vpc.vpc_id
  service_name  = "com.amazonaws.us-east-1.s3"
  endpoint_type = "Gateway"

  route_table_ids = concat(
    module.execution_vpc.private_route_table_ids,
    compact([module.execution_vpc.data_route_table_id])
  )

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-execution-s3-endpoint"
  })
}

###############################################################################
# Endpoint Security Groups (FREE - kept ready for re-enabling endpoints)
###############################################################################

module "endpoint_sg_control" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-control-endpoints-sg"
  description = "Security group for VPC Interface Endpoints in Control VPC"
  vpc_id      = module.control_vpc.vpc_id

  ingress = [
    {
      description = "HTTPS from Control VPC"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [local.control_vpc_cidr]
    }
  ]

  egress = [
    {
      description = "Allow all outbound"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = local.common_tags
}

module "endpoint_sg_execution" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-execution-endpoints-sg"
  description = "Security group for VPC Interface Endpoints in Execution VPC"
  vpc_id      = module.execution_vpc.vpc_id

  ingress = [
    {
      description = "HTTPS from Execution VPC"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [local.execution_vpc_cidr]
    }
  ]

  egress = [
    {
      description = "Allow all outbound"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = local.common_tags
}
