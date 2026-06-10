# Security Groups - Least-Privilege Matrices
# Epic: E05 - Networking (Dual VPC per env)
# Story: S025 - Security group least-privilege matrices
#
# Note: Cross-SG references use aws_security_group_rule to avoid cycles.

###############################################################################
# Control VPC Security Groups
###############################################################################

# ALB Security Group (public-facing)
module "sg_alb_control" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-control-alb-sg"
  description = "ALB in Control VPC - accepts HTTPS from internet"
  vpc_id      = module.control_vpc.vpc_id

  ingress = [
    {
      description = "HTTPS from internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  # Egress to ECS tasks added via aws_security_group_rule below
  egress = []

  tags = local.common_tags
}

# ECS Tasks Security Group (Control Plane services)
module "sg_ecs_control" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-control-ecs-sg"
  description = "ECS tasks in Control VPC"
  vpc_id      = module.control_vpc.vpc_id

  ingress = [
    {
      description = "From Execution VPC via peering (PrivateLink consumer)"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [local.execution_vpc_cidr]
    }
  ]

  egress = [
    {
      description = "HTTPS to AWS APIs (endpoints)"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = local.common_tags
}

# RDS Security Group (Control Plane database)
module "sg_rds_control" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-control-rds-sg"
  description = "RDS in Control VPC - accepts from ECS only"
  vpc_id      = module.control_vpc.vpc_id

  ingress = []
  egress  = []

  tags = local.common_tags
}

###############################################################################
# Cross-SG Rules (Control VPC) - breaks circular dependencies
###############################################################################

# ALB → ECS (egress from ALB to ECS on port 8080)
resource "aws_security_group_rule" "alb_to_ecs_control" {
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.sg_alb_control.id
  source_security_group_id = module.sg_ecs_control.id
  description              = "ALB to ECS tasks"
}

# ECS ← ALB (ingress to ECS from ALB on port 8080)
resource "aws_security_group_rule" "ecs_from_alb_control" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = module.sg_ecs_control.id
  source_security_group_id = module.sg_alb_control.id
  description              = "From ALB"
}

# ECS → RDS (egress from ECS to RDS on port 5432)
resource "aws_security_group_rule" "ecs_to_rds_control" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.sg_ecs_control.id
  source_security_group_id = module.sg_rds_control.id
  description              = "ECS to RDS"
}

# RDS ← ECS (ingress to RDS from ECS on port 5432)
resource "aws_security_group_rule" "rds_from_ecs_control" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.sg_rds_control.id
  source_security_group_id = module.sg_ecs_control.id
  description              = "PostgreSQL from ECS tasks"
}

###############################################################################
# Execution VPC Security Groups
###############################################################################

# ECS Tasks Security Group (Execution Plane workers)
module "sg_ecs_execution" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-execution-ecs-sg"
  description = "ECS worker tasks in Execution VPC"
  vpc_id      = module.execution_vpc.vpc_id

  ingress = [
    {
      description = "Internal health checks within SG"
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      self        = true
    }
  ]

  egress = [
    {
      description = "HTTPS to VPC endpoints and Control VPC"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = local.common_tags
}

# RDS Security Group (Execution Plane database)
module "sg_rds_execution" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-execution-rds-sg"
  description = "RDS in Execution VPC - accepts from ECS workers only"
  vpc_id      = module.execution_vpc.vpc_id

  ingress = []
  egress  = []

  tags = local.common_tags
}

###############################################################################
# Cross-SG Rules (Execution VPC)
###############################################################################

# ECS → RDS (egress from ECS to RDS on port 5432)
resource "aws_security_group_rule" "ecs_to_rds_execution" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.sg_ecs_execution.id
  source_security_group_id = module.sg_rds_execution.id
  description              = "ECS workers to RDS"
}

# RDS ← ECS (ingress to RDS from ECS on port 5432)
resource "aws_security_group_rule" "rds_from_ecs_execution" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.sg_rds_execution.id
  source_security_group_id = module.sg_ecs_execution.id
  description              = "PostgreSQL from ECS workers"
}
