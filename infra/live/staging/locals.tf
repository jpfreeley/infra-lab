# Staging Environment Locals
# Epic: E05 - Networking (Dual VPC per env)
# Story: S004 - Define CIDR plan and subnetting for staging

locals {
  project     = "infra-lab"
  environment = "staging"
  name_prefix = "${local.project}-${local.environment}"

  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Control VPC - management/orchestration workloads
  control_vpc_cidr = "10.0.32.0/20"
  control_public_subnets = [
    { cidr = "10.0.32.0/24", az = "us-east-1a" },
    { cidr = "10.0.33.0/24", az = "us-east-1b" },
    { cidr = "10.0.34.0/24", az = "us-east-1c" },
  ]
  control_private_subnets = [
    { cidr = "10.0.36.0/22", az = "us-east-1a" },
    { cidr = "10.0.40.0/22", az = "us-east-1b" },
    { cidr = "10.0.44.0/22", az = "us-east-1c" },
  ]
  control_data_subnets = [
    { cidr = "10.0.35.0/26", az = "us-east-1a" },
    { cidr = "10.0.35.64/26", az = "us-east-1b" },
    { cidr = "10.0.35.128/26", az = "us-east-1c" },
  ]

  # Execution VPC - tenant/worker workloads (restricted egress)
  execution_vpc_cidr = "10.0.48.0/20"
  execution_public_subnets = [
    { cidr = "10.0.48.0/24", az = "us-east-1a" },
    { cidr = "10.0.49.0/24", az = "us-east-1b" },
    { cidr = "10.0.50.0/24", az = "us-east-1c" },
  ]
  execution_private_subnets = [
    { cidr = "10.0.52.0/22", az = "us-east-1a" },
    { cidr = "10.0.56.0/22", az = "us-east-1b" },
    { cidr = "10.0.60.0/22", az = "us-east-1c" },
  ]
  execution_data_subnets = [
    { cidr = "10.0.51.0/26", az = "us-east-1a" },
    { cidr = "10.0.51.64/26", az = "us-east-1b" },
    { cidr = "10.0.51.128/26", az = "us-east-1c" },
  ]

  # VPC Endpoint services for Control VPC
  interface_endpoints = [
    "com.amazonaws.us-east-1.ecr.api",
    "com.amazonaws.us-east-1.ecr.dkr",
    "com.amazonaws.us-east-1.logs",
    "com.amazonaws.us-east-1.monitoring",
    "com.amazonaws.us-east-1.secretsmanager",
    "com.amazonaws.us-east-1.sqs",
    "com.amazonaws.us-east-1.ssm",
    "com.amazonaws.us-east-1.kms",
    "com.amazonaws.us-east-1.sts",
  ]

  common_tags = {
    Environment = local.environment
  }
}
