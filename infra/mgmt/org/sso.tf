data "aws_ssoadmin_instances" "current" {}

locals {
  sso_instance_arn = data.aws_ssoadmin_instances.current.arns[0]
}

####
# Permission Sets - E04-S002
#
# Defines role-based permission sets for IAM Identity Center:
# - AdministratorAccess: Full admin (break-glass, org management)
# - PlatformEngineer: Infrastructure management (Terraform, networking, compute)
# - Developer: Application-level access (Lambda, ECS, S3, DynamoDB)
# - SecurityAuditor: Security review and compliance (read + security services)
# - ReadOnlyAccess: View-only access for all services
####

# --- AdministratorAccess ---
resource "aws_ssoadmin_permission_set" "admin_access" {
  name             = "AdministratorAccess"
  description      = "Full administrative access - break-glass and org management only"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin_attach" {
  # checkov:skip=CKV_AWS_274:AdministratorAccess required for break-glass org management
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.admin_access.arn
}

# --- PlatformEngineer ---
resource "aws_ssoadmin_permission_set" "platform_engineer" {
  name             = "PlatformEngineer"
  description      = "Infrastructure management - Terraform, networking, compute, storage, IAM"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "platform_power_user" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
  permission_set_arn = aws_ssoadmin_permission_set.platform_engineer.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "platform_iam_read" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.platform_engineer.arn
}

# --- Developer ---
resource "aws_ssoadmin_permission_set" "developer" {
  name             = "Developer"
  description      = "Application-level access - Lambda, ECS, S3, DynamoDB, CloudWatch"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_lambda" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_ecs" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_s3" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_dynamodb" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_cloudwatch" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccessV2"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_logs" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
}

# --- SecurityAuditor ---
resource "aws_ssoadmin_permission_set" "security_auditor" {
  name             = "SecurityAuditor"
  description      = "Security review - read-all plus security service management"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "security_read_only" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.security_auditor.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "security_hub_access" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AWSSecurityHubFullAccess"
  permission_set_arn = aws_ssoadmin_permission_set.security_auditor.arn
}

resource "aws_ssoadmin_managed_policy_attachment" "security_guardduty" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AmazonGuardDutyReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.security_auditor.arn
}

# --- ReadOnlyAccess ---
resource "aws_ssoadmin_permission_set" "read_only_access" {
  name             = "ReadOnlyAccess"
  description      = "View-only access to all AWS services"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly_attach" {
  instance_arn       = local.sso_instance_arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.read_only_access.arn
}

####
# Group Assignments - E04-S003
#
# Assigns SSO groups to permission sets in specific accounts.
# Groups are managed in IAM Identity Center directory.
####

# Assign AdministratorAccess to admin group in Management account
resource "aws_ssoadmin_account_assignment" "admin_group_management" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin_access.arn
  principal_id       = "02672018-6ff7-4b90-b5ee-8b72b65c119d" # AWSSecurityAuditPowerUsers
  principal_type     = "GROUP"
  target_id          = "551452024305" # Management account
  target_type        = "AWS_ACCOUNT"
}

# Assign ReadOnlyAccess to audit group in Audit account
resource "aws_ssoadmin_account_assignment" "readonly_user_audit" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only_access.arn
  principal_id       = "17e639ec-e64d-4718-8c06-f9e87c679d38" # AWSAuditAccountAdmins
  principal_type     = "GROUP"
  target_id          = "881413600100" # Audit account
  target_type        = "AWS_ACCOUNT"
}
