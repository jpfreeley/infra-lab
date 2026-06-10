# Dev Environment Locals
# Epic: E05 - Networking (Dual VPC per env)
# Story: S001 - Define CIDR plan and subnetting for dev

locals {
  project     = "infra-lab"
  environment = var.environment
  name_prefix = "${local.project}-${local.environment}"

  # Control VPC - management/orchestration workloads
  control_vpc_cidr = "10.0.0.0/20"
  control_public_subnets = [
    { cidr = "10.0.0.0/24", az = "us-east-1a" },
    { cidr = "10.0.1.0/24", az = "us-east-1b" },
    { cidr = "10.0.2.0/24", az = "us-east-1c" },
  ]
  control_private_subnets = [
    { cidr = "10.0.4.0/22", az = "us-east-1a" },
    { cidr = "10.0.8.0/22", az = "us-east-1b" },
    { cidr = "10.0.12.0/22", az = "us-east-1c" },
  ]
  control_data_subnets = [
    { cidr = "10.0.3.0/26", az = "us-east-1a" },
    { cidr = "10.0.3.64/26", az = "us-east-1b" },
    { cidr = "10.0.3.128/26", az = "us-east-1c" },
  ]

  # Execution VPC - tenant/worker workloads (restricted egress)
  execution_vpc_cidr = "10.0.16.0/20"
  execution_public_subnets = [
    { cidr = "10.0.16.0/24", az = "us-east-1a" },
    { cidr = "10.0.17.0/24", az = "us-east-1b" },
    { cidr = "10.0.18.0/24", az = "us-east-1c" },
  ]
  execution_private_subnets = [
    { cidr = "10.0.20.0/22", az = "us-east-1a" },
    { cidr = "10.0.24.0/22", az = "us-east-1b" },
    { cidr = "10.0.28.0/22", az = "us-east-1c" },
  ]
  execution_data_subnets = [
    { cidr = "10.0.19.0/26", az = "us-east-1a" },
    { cidr = "10.0.19.64/26", az = "us-east-1b" },
    { cidr = "10.0.19.128/26", az = "us-east-1c" },
  ]

  common_tags = {
    Environment = local.environment
  }
}
