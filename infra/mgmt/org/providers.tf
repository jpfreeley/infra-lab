terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Previously had no backend block at all (defaulted to local state) —
  # unlike every infra/live/* root, which already uses this same bucket.
  # That gap meant this module's state lived only on whatever machine last
  # ran it; a machine migration lost it, requiring a manual restore from an
  # SMB backup on 2026-08-14 before this block was added. Matches the
  # mgmt/backend module's own backend config (same bucket/lock table).
  backend "s3" {
    bucket         = "infra-lab-tf-state-551452024305"
    key            = "mgmt/org/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "infra-lab-tf-state-locks"
    encrypt        = true
    kms_key_id     = "alias/aws/s3"
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
  alias   = "audit"
  region  = "us-east-1"
  profile = "infra-lab-security-audit"
}
