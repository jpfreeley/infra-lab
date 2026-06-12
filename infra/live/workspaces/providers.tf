# WorkSpaces Account Provider Configuration
# Epic: E13 - AWS WorkSpaces Account
# Story: E13-S012 - Create Terraform live root for WorkSpaces account
# Account ID: 815802018602

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "infra-lab-tf-state-551452024305"
    key            = "live/workspaces/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "infra-lab-tf-state-locks"
    encrypt        = true
    profile        = "infra-lab"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  assume_role {
    role_arn     = "arn:aws:iam::815802018602:role/OrganizationAccountAccessRole"
    session_name = "terraform-workspaces"
  }

  default_tags {
    tags = {
      Project     = "infra-lab"
      Environment = "sandbox"
      ManagedBy   = "terraform"
      Owner       = "infra-team"
    }
  }
}
