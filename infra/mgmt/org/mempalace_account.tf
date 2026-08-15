# MemPalace Dedicated Account
# ADR-034: Shared MemPalace Server as a Portable App on Dedicated Infra
#
# Same rationale as the WorkSpaces account (ADR-031): this workload's
# lifecycle (always-on, personal utility) diverges from dev's scale-to-zero,
# torn-down-often design (ADR-030), so it gets its own account under the
# Workloads OU rather than being squeezed into infra/live/dev.

###############################################################################
# MemPalace Account (under Workloads OU)
###############################################################################

resource "aws_organizations_account" "mempalace" {
  name      = "infra-lab-mempalace"
  email     = "infra-lab+mempalace@${var.org_email_domain}"
  parent_id = aws_organizations_organizational_unit.workloads.id

  role_name = "OrganizationAccountAccessRole"

  # Prevent accidental deletion — account closure is a manual process
  close_on_deletion = false

  tags = merge(local.common_tags, {
    Service = "mempalace"
  })

  lifecycle {
    # Prevent accidental account deletion via Terraform
    prevent_destroy = true
  }
}

###############################################################################
# MemPalace Account SCP - Service Boundary
# Narrower than the WorkSpaces SCP (no lambda/apigateway/dynamodb self-service
# API surface here) — only what mempalace_server's module actually uses.
###############################################################################

data "aws_iam_policy_document" "scp_mempalace_service_boundary" {
  statement {
    sid    = "DenyNonMempalaceServices"
    effect = "Deny"
    not_actions = [
      # Compute for the app itself
      "ecs:*",
      "ec2:*", # Fargate ENIs (awsvpc mode), EFS mount target ENIs, security groups
      "elasticfilesystem:*",
      "elasticloadbalancing:*",
      "wafv2:*",

      # Encryption and secrets
      "kms:*",
      "secretsmanager:*",

      # IAM (task roles) and identity
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

      # S3 for Terraform state / flow logs
      "s3:*",

      # Service Quotas (required to view/adjust account limits)
      "servicequotas:*",

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

resource "aws_organizations_policy" "mempalace_service_boundary" {
  name        = "${local.project_name}-mempalace-service-boundary"
  description = "Restrict the MemPalace account to only the services its ECS Fargate deployment uses."
  content     = data.aws_iam_policy_document.scp_mempalace_service_boundary.json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = local.common_tags
}

resource "aws_organizations_policy_attachment" "mempalace_service_boundary" {
  policy_id = aws_organizations_policy.mempalace_service_boundary.id
  target_id = aws_organizations_account.mempalace.id
}

###############################################################################
# Region restriction, security-services protection, IAM-user denial, and
# leave-org denial are already inherited from the Workloads OU / root, same
# as the WorkSpaces account.
###############################################################################
