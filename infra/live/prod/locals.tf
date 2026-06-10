# Prod Environment Locals
# Epic: E05 - Networking (Dual VPC per env)
# Story: S007 - Define CIDR plan and subnetting for prod

locals {
  project     = "infra-lab"
  environment = var.environment
  name_prefix = "${local.project}-${local.environment}"

  # Control VPC - management/orchestration workloads
  control_vpc_cidr = "10.0.64.0/20"
  control_public_subnets = [
    { cidr = "10.0.64.0/24", az = "us-east-1a" },
    { cidr = "10.0.65.0/24", az = "us-east-1b" },
    { cidr = "10.0.66.0/24", az = "us-east-1c" },
  ]
  control_private_subnets = [
    { cidr = "10.0.68.0/22", az = "us-east-1a" },
    { cidr = "10.0.72.0/22", az = "us-east-1b" },
    { cidr = "10.0.76.0/22", az = "us-east-1c" },
  ]
  control_data_subnets = [
    { cidr = "10.0.67.0/26", az = "us-east-1a" },
    { cidr = "10.0.67.64/26", az = "us-east-1b" },
    { cidr = "10.0.67.128/26", az = "us-east-1c" },
  ]

  # Execution VPC - tenant/worker workloads (restricted egress)
  execution_vpc_cidr = "10.0.80.0/20"
  execution_public_subnets = [
    { cidr = "10.0.80.0/24", az = "us-east-1a" },
    { cidr = "10.0.81.0/24", az = "us-east-1b" },
    { cidr = "10.0.82.0/24", az = "us-east-1c" },
  ]
  execution_private_subnets = [
    { cidr = "10.0.84.0/22", az = "us-east-1a" },
    { cidr = "10.0.88.0/22", az = "us-east-1b" },
    { cidr = "10.0.92.0/22", az = "us-east-1c" },
  ]
  execution_data_subnets = [
    { cidr = "10.0.83.0/26", az = "us-east-1a" },
    { cidr = "10.0.83.64/26", az = "us-east-1b" },
    { cidr = "10.0.83.128/26", az = "us-east-1c" },
  ]

  common_tags = {
    Environment = local.environment
  }
}
