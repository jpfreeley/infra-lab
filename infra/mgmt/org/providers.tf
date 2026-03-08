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

# Replica provider (Management Account)
provider "aws" {
  alias   = "replica"
  region  = "us-west-2"
  profile = "infra-lab"
}

# Delegated Admin Replica provider (Log Archive Account)
provider "aws" {
  alias   = "delegated_admin_replica"
  region  = "us-west-2"
  profile = "infra-lab-log-archive"
}

provider "aws" {
  alias  = "audit"
  region = var.region
  # profile = "infra-lab-security-audit" # Remove or comment this
  assume_role {
    role_arn = "arn:aws:iam::${var.security_audit_account_id}:role/OrganizationAccountAccessRole"
  }
}
