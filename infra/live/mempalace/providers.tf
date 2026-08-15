# MemPalace Account Provider Configuration
# ADR-034: Shared MemPalace Server as a Portable App on Dedicated Infra
#
# No profile hardcoded anywhere in this file (backend or provider) — this
# needs to work both locally (AWS_PROFILE=infra-lab env var, or
# -backend-config="profile=infra-lab" at init time) and from GitHub Actions
# (OIDC-derived credentials as env vars, no named profile exists there).
# Backend blocks can't reference variables at all (a hard Terraform
# limitation), which is why the backend profile is omitted rather than
# parameterized — pass it via -backend-config locally if AWS_PROFILE isn't
# already set in the shell.

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
    key            = "live/mempalace/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "infra-lab-tf-state-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  # Empty string (the CI default — see variables.tf) means "no named
  # profile," falling back to the standard credential chain (env vars from
  # GitHub Actions' OIDC step). A literal empty string passed straight to
  # the provider isn't reliably treated as unset across provider versions,
  # so this ternary makes it explicitly null instead.
  profile = var.aws_profile != "" ? var.aws_profile : null

  assume_role {
    role_arn     = "arn:aws:iam::${var.mempalace_account_id}:role/OrganizationAccountAccessRole"
    session_name = "terraform-mempalace"
  }

  default_tags {
    tags = {
      Project     = "infra-lab"
      Environment = "mempalace"
      ManagedBy   = "terraform"
      Owner       = "infra-team"
    }
  }
}

# The lintwiselabs.com Route53 zone lives in the management account, not
# the mempalace account — ACM DNS validation needs a record written there.
# No assume_role: base credentials (local profile or CI's OIDC session)
# already ARE the management account identity, no second hop needed.
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
