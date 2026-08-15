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

  # Had no backend block (defaulted to local state), same gap found and
  # fixed in infra/mgmt/org on 2026-08-14. This module holds no resources
  # today (providers.tf + variables.tf only) so there was nothing at risk,
  # but fixing it now for consistency rather than leaving a second copy of
  # the same gap for whenever this module actually grows resources.
  backend "s3" {
    bucket         = "infra-lab-tf-state-551452024305"
    key            = "live/shared/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "infra-lab-tf-state-locks"
    encrypt        = true
    kms_key_id     = "alias/aws/s3"
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
