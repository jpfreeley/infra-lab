terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider (Management Account)
provider "aws" {
  region  = "us-east-1"
  profile = "infra-lab"
}

# Delegated Admin provider (Log Archive Account)
# This is required for GuardDuty/SecurityHub organization-wide config
provider "aws" {
  alias   = "delegated_admin"
  region  = "us-east-1"
  profile = "infra-lab-log-archive"
}
