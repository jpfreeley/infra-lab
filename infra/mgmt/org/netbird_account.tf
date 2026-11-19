# NetBird Dedicated Account
# ADR-037: Self-Hosted NetBird Server in a Dedicated Account, Torn Down When Idle
#
# Same account-factory pattern as WorkSpaces (ADR-031) and MemPalace
# (ADR-034). This one exists for a stronger reason than lifecycle alone:
# the NetBird control plane decides which peers can join the WireGuard
# overlay, so whoever controls this account can reach every device on it.
# It gets its own boundary rather than sharing the MemPalace account, which
# also hosts another team's instance.

###############################################################################
# NetBird Account (under Workloads OU)
###############################################################################

resource "aws_organizations_account" "netbird" {
  name      = "infra-lab-netbird"
  email     = "infra-lab+netbird@${var.org_email_domain}"
  parent_id = aws_organizations_organizational_unit.workloads.id

  role_name = "OrganizationAccountAccessRole"

  # Prevent accidental deletion: account closure is a manual process
  close_on_deletion = false

  tags = merge(local.common_tags, {
    Service = "netbird"
  })

  lifecycle {
    # Prevent accidental account deletion via Terraform
    prevent_destroy = true
  }
}

###############################################################################
# NetBird Account SCP - Service Boundary
# Only what infra/modules/netbird_server and infra/live/netbird use. Narrower
# than the MemPalace SCP: no wafv2 (NLB front end, no WAF) and no events
# (the lease-check schedule lives in the management account, ADR-037).
# acm is listed because tls_mode "nlb" issues the certificate in this
# account.
###############################################################################

data "aws_iam_policy_document" "scp_netbird_service_boundary" {
  statement {
    sid    = "DenyNonNetbirdServices"
    effect = "Deny"
    not_actions = [
      # Compute and networking for the app itself
      "ecs:*",
      "ec2:*", # Fargate ENIs (awsvpc mode), EFS mount target ENIs, security groups, VPC
      "elasticfilesystem:*",
      "elasticloadbalancing:*",
      "acm:*",

      # Encryption and secrets
      "kms:*",
      "secretsmanager:*",

      # IAM (task roles) and identity
      "iam:*",
      "sts:*",

      # Observability
      "cloudwatch:*",
      "logs:*",

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

resource "aws_organizations_policy" "netbird_service_boundary" {
  name        = "${local.project_name}-netbird-service-boundary"
  description = "Restrict the NetBird account to only the services its ECS Fargate + NLB deployment uses."
  content     = data.aws_iam_policy_document.scp_netbird_service_boundary.json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = local.common_tags
}

resource "aws_organizations_policy_attachment" "netbird_service_boundary" {
  policy_id = aws_organizations_policy.netbird_service_boundary.id
  target_id = aws_organizations_account.netbird.id
}

###############################################################################
# Region restriction, security-services protection, IAM-user denial, and
# leave-org denial are inherited from the Workloads OU / root, same as the
# WorkSpaces and MemPalace accounts.
###############################################################################
