# Dev Environment Provider Configuration
# Epic: E05 - Networking (Dual VPC per env)

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
    key            = "live/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "infra-lab-tf-state-locks"
    encrypt        = true
    profile        = "infra-lab"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "infra-lab"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "infra-team"
    }
  }
}
