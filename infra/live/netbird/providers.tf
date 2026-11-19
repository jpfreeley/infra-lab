# NetBird Account Provider Configuration
# ADR-037: Self-Hosted NetBird Server in a Dedicated Account, Torn Down When Idle
#
# Same shape as infra/live/mempalace/providers.tf: no profile hardcoded in
# the backend (pass -backend-config="profile=infra-lab" locally if
# AWS_PROFILE isn't set; GitHub Actions supplies OIDC credentials as env
# vars), and the default provider assumes OrganizationAccountAccessRole in
# the NetBird account from the management account's credentials.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "infra-lab-tf-state-551452024305"
    key            = "live/netbird/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "infra-lab-tf-state-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  # Empty string (the CI value) means "no named profile": fall back to the
  # standard credential chain. Explicit null, same reasoning as mempalace.
  profile = var.aws_profile != "" ? var.aws_profile : null

  assume_role {
    role_arn     = "arn:aws:iam::${var.netbird_account_id}:role/OrganizationAccountAccessRole"
    session_name = "terraform-netbird"
  }

  default_tags {
    tags = {
      Project     = "infra-lab"
      Environment = "netbird"
      ManagedBy   = "terraform"
      Owner       = "infra-team"
    }
  }
}

# The lintwiselabs.com Route53 zone lives in the management account. No
# assume_role: the base credentials already are the management account.
provider "aws" {
  alias   = "dns"
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = {
      Project   = "infra-lab"
      ManagedBy = "terraform"
    }
  }
}
