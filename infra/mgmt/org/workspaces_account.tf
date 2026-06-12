# WorkSpaces Dedicated Account
# Epic: E13 - AWS WorkSpaces Account
# Story: E13-S001 - Provision dedicated WorkSpaces account via Account Factory

###############################################################################
# WorkSpaces Account (under Workloads OU)
###############################################################################

resource "aws_organizations_account" "workspaces" {
  name      = "infra-lab-workspaces"
  email     = "infra-lab+workspaces@${var.org_email_domain}"
  parent_id = aws_organizations_organizational_unit.workloads.id

  role_name = "OrganizationAccountAccessRole"

  # Prevent accidental deletion — account closure is a manual process
  close_on_deletion = false

  tags = merge(local.common_tags, {
    Story   = "E13-S001"
    Service = "workspaces"
  })

  lifecycle {
    # Prevent accidental account deletion via Terraform
    prevent_destroy = true
  }
}

###############################################################################
# WorkSpaces Account SCP - Service Boundary
# Story: E13-S013 - Implement SCPs and guardrails for WorkSpaces account
###############################################################################

data "aws_iam_policy_document" "scp_workspaces_service_boundary" {
  statement {
    sid    = "DenyNonWorkspacesServices"
    effect = "Deny"
    not_actions = [
      # WorkSpaces and related
      "workspaces:*",
      "workspaces-web:*",
      "ds:*",

      # Required infrastructure services
      "ec2:*",
      "kms:*",
      "iam:*",
      "sts:*",

      # Observability
      "cloudwatch:*",
      "logs:*",
      "events:*",

      # Budgets and cost
      "budgets:*",
      "ce:*",

      # Required baseline services (Control Tower / guardrails)
      "cloudtrail:*",
      "config:*",
      "guardduty:*",
      "securityhub:*",
      "access-analyzer:*",
      "organizations:Describe*",
      "organizations:List*",

      # S3 for flow logs and state
      "s3:*",

      # DynamoDB for desktop tracking
      "dynamodb:*",

      # Lambda for self-service API
      "lambda:*",
      "apigateway:*",

      # Support
      "support:*",
      "trustedadvisor:*",

      # SSO access
      "sso:*",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.scp_exempt_role_arns
    }
  }
}

resource "aws_organizations_policy" "workspaces_service_boundary" {
  name        = "${local.project_name}-workspaces-service-boundary"
  description = "Restrict WorkSpaces account to only WorkSpaces-related AWS services."
  content     = data.aws_iam_policy_document.scp_workspaces_service_boundary.json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = merge(local.common_tags, { Story = "E13-S013" })
}

resource "aws_organizations_policy_attachment" "workspaces_service_boundary" {
  policy_id = aws_organizations_policy.workspaces_service_boundary.id
  target_id = aws_organizations_account.workspaces.id
}

###############################################################################
# Region restriction already inherited from Workloads OU (deny_non_approved_regions)
# Security services protection already inherited from Workloads OU (deny_disable_security_services)
# IAM user denial already inherited from Workloads OU (deny_iam_users)
# Leave org denial already inherited from root (deny_leave_organization)
###############################################################################
