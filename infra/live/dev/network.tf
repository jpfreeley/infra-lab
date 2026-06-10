# Network Resources (VPC, Subnets, Security Groups)
# Epic: E06 - Compute (ECS Fargate API + Workers)
# Stub: These reference VPC/SG modules for ECS service dependencies.
# Full VPC module implementation tracked in a future epic.

###############################################################################
# Control Plane VPC (API services)
###############################################################################

module "control_vpc" {
  source = "../../modules/vpc"

  name        = "${local.name_prefix}-control"
  cidr_block  = var.vpc_cidr_control
  environment = var.environment
  tags        = local.common_tags
}

###############################################################################
# Execution Plane VPC (Worker services)
###############################################################################

module "execution_vpc" {
  source = "../../modules/vpc"

  name        = "${local.name_prefix}-execution"
  cidr_block  = var.vpc_cidr_execution
  environment = var.environment
  tags        = local.common_tags
}

###############################################################################
# Security Groups
###############################################################################

module "sg_alb_control" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-alb-control"
  description = "ALB security group for control plane"
  vpc_id      = module.control_vpc.vpc_id

  ingress = [
    {
      description = "HTTPS from internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTP redirect"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "Test listener for Blue/Green"
      from_port   = 8443
      to_port     = 8443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = local.common_tags
}

module "sg_ecs_control" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-ecs-control"
  description = "ECS tasks security group for control plane"
  vpc_id      = module.control_vpc.vpc_id

  ingress = [
    {
      description     = "Traffic from ALB"
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      security_groups = [module.sg_alb_control.id]
    }
  ]

  tags = local.common_tags
}

module "sg_ecs_execution" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-ecs-execution"
  description = "ECS tasks security group for execution plane"
  vpc_id      = module.execution_vpc.vpc_id

  ingress = []

  tags = local.common_tags
}
