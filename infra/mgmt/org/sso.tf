data "aws_ssoadmin_instances" "current" {}

locals {
  sso_instance_arn = data.aws_ssoadmin_instances.current.arns[0]
}

# Define Permission Sets
resource "aws_ssoadmin_permission_set" "admin_access" {
  name             = "AdministratorAccess"
  description      = "Full administrative access to AWS accounts"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H" # 8 hours
}

resource "aws_ssoadmin_permission_set" "read_only_access" {
  name             = "ReadOnlyAccess"
  description      = "Read-only access to AWS accounts"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
}

# Attach AWS managed policies to Permission Sets

resource "aws_ssoadmin_managed_policy_attachment" "admin_attach" {
  # checkov:skip=CKV_AWS_274 "AdministratorAccess is required for OrganizationAccountAccessRole to manage Audit account"
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.admin_access.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly_attach" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.read_only_access.arn
}

# Example: Assign Permission Sets to Users or Groups in Specific Accounts
# Replace placeholders with actual values:
# - USER_IDENTITY_STORE_ID: Get from Identity Store (e.g., via `aws identitystore list-users`)
# - GROUP_IDENTITY_STORE_ID: Get from Identity Store (e.g., via `aws identitystore list-groups`)
# - TARGET_ACCOUNT_ID: AWS Account ID to assign the permission set to

# Assign AdministratorAccess to a group in the Management account
resource "aws_ssoadmin_account_assignment" "admin_group_management" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin_access.arn
  principal_id       = "02672018-6ff7-4b90-b5ee-8b72b65c119d" # AWSSecurityAuditPowerUsers
  principal_type     = "GROUP"
  target_id          = "551452024305" # Management account ID
  target_type        = "AWS_ACCOUNT"
}

# Assign ReadOnlyAccess to a user in the Audit account
resource "aws_ssoadmin_account_assignment" "readonly_user_audit" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only_access.arn
  principal_id       = "17e639ec-e64d-4718-8c06-f9e87c679d38" # AWSAuditAccountAdmins
  principal_type     = "GROUP"
  target_id          = "881413600100" # Audit account ID
  target_type        = "AWS_ACCOUNT"
}
