# Local Values
# Epic: E06 - Compute (ECS Fargate API + Workers)

locals {
  name_prefix = "infra-lab-${var.environment}"
  environment = var.environment

  common_tags = {
    Project     = "infra-lab"
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "infra-team"
  }
}
