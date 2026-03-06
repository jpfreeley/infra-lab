# Standard AWS Provider Configuration
# Epic: E02 - Terraform Foundations + State
# Story: S003 - Multi-account provider + AssumeRole strategy

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# The default provider for the management/shared account
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "infra-lab"
      ManagedBy = "terraform"
      Owner     = "infra-team"
    }
  }
}

# Aliased provider for target environment deployments via AssumeRole
# This allows CI/CD or local admin to deploy into workload accounts
provider "aws" {
  alias  = "target"
  region = var.aws_region

  assume_role {
    # The ARN of the role to assume in the target account
    role_arn     = var.target_role_arn
    session_name = "TerraformDeployment"
    external_id  = var.target_external_id
  }

  default_tags {
    tags = {
      Project     = "infra-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
