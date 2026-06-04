####
# IAM Hardening Controls - E04-S009, S010, S012, S015
####

# --- E04-S010: IAM Access Analyzer ---
# Organization-level analyzer to detect external access and unused permissions
resource "aws_accessanalyzer_analyzer" "org" {
  analyzer_name = "${local.project_name}-org-analyzer"
  type          = "ORGANIZATION"

  tags = merge(local.common_tags, { Story = "E04-S010" })

  depends_on = [aws_organizations_organization.org]
}

# --- E04-S012: SCP to block root user actions except break-glass ---
data "aws_iam_policy_document" "scp_deny_root_user" {
  statement {
    sid    = "DenyRootUserActions"
    effect = "Deny"
    actions = [
      "iam:*",
      "organizations:*",
      "account:*",
      "billing:*"
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }
}

resource "aws_organizations_policy" "deny_root_user" {
  name        = "${local.project_name}-${local.environment}-deny-root-user"
  description = "Deny root user actions in member accounts. Root should only be used for break-glass via the management account."
  content     = data.aws_iam_policy_document.scp_deny_root_user.json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = merge(local.common_tags, { Story = "E04-S012" })
}

resource "aws_organizations_policy_attachment" "deny_root_workloads" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "deny_root_sandbox" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}

resource "aws_organizations_policy_attachment" "deny_root_infrastructure" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = aws_organizations_organizational_unit.infrastructure.id
}

# --- E04-S015: CloudTrail Insights ---
# NOTE: CloudTrail Lake (Event Data Stores) is no longer accepting new customers
# as of 2026. Insights are enabled on the existing Organization Trail instead.
# CloudTrail Insights on the org trail detect anomalous API activity automatically.
# No additional infrastructure needed — the org trail in cloudtrail.tf handles this.
