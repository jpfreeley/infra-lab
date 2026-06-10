# Standard AWS Provider Configuration
# Epic: E06 - Compute (ECS Fargate API + Workers)

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "infra-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "infra-team"
    }
  }
}
