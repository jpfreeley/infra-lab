# WorkSpaces Account Locals
# Epic: E13 - AWS WorkSpaces Account
# Pivoted to EC2 + NICE DCV for cost optimization

locals {
  project     = "infra-lab"
  environment = var.environment
  name_prefix = "${local.project}-${local.environment}"

  # WorkSpaces VPC - allocated from reserved block (10.0.96.0/19)
  # Using 10.0.96.0/20 for this account
  vpc_cidr = "10.0.96.0/20"

  public_subnets = [
    { cidr = "10.0.96.0/24", az = "us-east-1a" },
    { cidr = "10.0.97.0/24", az = "us-east-1b" },
  ]

  # Private subnets for EC2 desktop instances
  private_subnets = [
    { cidr = "10.0.100.0/22", az = "us-east-1a" },
    { cidr = "10.0.104.0/22", az = "us-east-1b" },
  ]

  common_tags = {
    Environment = local.environment
    Service     = "workspaces"
  }
}
