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
  scp_exempt_role_arns = concat(
    [
      "arn:aws:iam::*:role/AWSControlTowerExecution",
      "arn:aws:iam::*:role/AWSCloudFormationStackSetExecutionRole",
      "arn:aws:iam::*:role/OrganizationAccountAccessRole",
      "arn:aws:iam::*:role/AWSReservedSSO_AWSAdministratorAccess_*"
    ],
    var.scp_exempt_role_arns
  )
}
