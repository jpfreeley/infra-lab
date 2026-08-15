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

  # Deliberately no backend block. Same gap exists here as the one found
  # and fixed in infra/mgmt/org on 2026-08-14 (local state only, no
  # remote backup); tried adding one here too, but it broke
  # infra-compliance.yml's CI check, which relies on `terraform init
  # -backend=false` for an offline plan and errors once an explicit
  # backend block exists (confirmed by reproducing the CI failure
  # locally, not guessed). Reverted rather than touching that CI job:
  # this module holds zero real resources today (providers.tf +
  # variables.tf only), so there's nothing actually at risk from staying
  # on local state, worth fixing properly (alongside the CI job) only
  # once this module has real resources to protect.
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
