locals {
  project_name = "infra-lab"
  environment  = "mgmt"

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = "jpfreeley"
    Repo        = "infra-lab"
  }

  # Roles that should be exempt from SCP restrictions to prevent lockout
  # (Moved from scps.tf to keep locals together)
  scp_exempt_role_arns = concat(
    [
      "arn:aws:iam::*:role/AWSControlTowerExecution",
      "arn:aws:iam::*:role/AWSCloudFormationStackSetExecutionRole",
      "arn:aws:iam::*:role/OrganizationAccountAccessRole"
    ],
    var.scp_exempt_role_arns
  )
}
