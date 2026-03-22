####
# Service Control Policies (SCPs) - E03-S009 & E03-S010
####

# 1. Deny IAM User & Access Key Creation (S009)
data "aws_iam_policy_document" "scp_deny_iam_users" {
  statement {
    sid    = "DenyIAMUsersAndLongLivedCredentials"
    effect = "Deny"
    actions = [
      "iam:CreateUser", "iam:DeleteUser", "iam:UpdateUser",
      "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:DeleteLoginProfile",
      "iam:CreateAccessKey", "iam:UpdateAccessKey", "iam:DeleteAccessKey",
      "iam:CreateServiceSpecificCredential", "iam:CreateSigningCertificate"
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.scp_exempt_role_arns
    }
  }
}

# 2. Deny Disabling Security Services (S009)
data "aws_iam_policy_document" "scp_deny_disable_security_services" {
  statement {
    sid    = "DenyDisablingCloudTrail"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors", "cloudtrail:PutInsightSelectors",
      "cloudtrail:PutResourcePolicy"
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.scp_exempt_role_arns
    }
  }

  statement {
    sid    = "DenyDisablingAWSConfig"
    effect = "Deny"
    actions = [
      "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel", "config:PutConfigurationRecorder",
      "config:PutDeliveryChannel"
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.scp_exempt_role_arns
    }
  }

  statement {
    sid    = "DenyDisablingGuardDuty"
    effect = "Deny"
    actions = [
      "guardduty:DeleteDetector", "guardduty:ArchiveFindings", "guardduty:UpdateDetector",
      "guardduty:DisassociateFromMasterAccount", "guardduty:DisassociateMembers"
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.scp_exempt_role_arns
    }
  }
}

# 3. Deny Leaving the Organization (S009)
data "aws_iam_policy_document" "scp_deny_leave_organization" {
  statement {
    sid       = "DenyLeavingOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.scp_exempt_role_arns
    }
  }
}

# 4. Deny Non-Approved Regions (S010)
data "aws_iam_policy_document" "scp_deny_non_approved_regions" {
  statement {
    sid    = "DenyNonApprovedRegions"
    effect = "Deny"
    not_actions = [
      "a4b:*", "acm:*", "aws-marketplace-management:*", "aws-marketplace:*",
      "budgets:*", "ce:*", "chime:*", "cloudfront:*", "config:*", "cur:*",
      "directconnect:*", "ec2:DescribeRegions", "ec2:DescribeTransitGateways",
      "fms:*", "globalaccelerator:*", "health:*", "iam:*", "importexport:*",
      "kms:*", "mobileanalytics:*", "networkmanager:*", "organizations:*",
      "pricing:*", "route53:*", "route53domains:*", "route53resolver:*",
      "s3:GetAccountPublic*", "s3:ListAllMyBuckets", "s3:PutAccountPublic*",
      "shield:*", "sts:*", "support:*", "trustedadvisor:*", "waf-regional:*",
      "waf:*", "wafv2:*"
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1", "us-west-2"]
    }
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.scp_exempt_role_arns
    }
  }
}

resource "aws_organizations_policy" "deny_iam_users" {
  name        = "${local.project_name}-${local.environment}-deny-iam-users"
  description = "Deny creation and management of IAM users and long-lived user credentials."
  content     = data.aws_iam_policy_document.scp_deny_iam_users.json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = merge(local.common_tags, { Story = "E03-S009" })
}

resource "aws_organizations_policy" "deny_disable_security_services" {
  name        = "${local.project_name}-${local.environment}-deny-disable-security-services"
  description = "Deny disabling or mutating CloudTrail, Config, and GuardDuty."
  content     = data.aws_iam_policy_document.scp_deny_disable_security_services.json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = merge(local.common_tags, { Story = "E03-S009" })
}

resource "aws_organizations_policy" "deny_leave_organization" {
  name        = "${local.project_name}-${local.environment}-deny-leave-organization"
  description = "Deny member accounts from leaving the AWS Organization."
  content     = data.aws_iam_policy_document.scp_deny_leave_organization.json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = merge(local.common_tags, { Story = "E03-S009" })
}

resource "aws_organizations_policy" "deny_non_approved_regions" {
  name        = "${local.project_name}-${local.environment}-deny-non-approved-regions"
  description = "Deny resource creation in non-approved regions (us-east-1, us-west-2)."
  content     = data.aws_iam_policy_document.scp_deny_non_approved_regions.json
  type        = "SERVICE_CONTROL_POLICY"
  tags        = merge(local.common_tags, { Story = "E03-S010" })
}

# Attachments
resource "aws_organizations_policy_attachment" "deny_leave_organization_root" {
  policy_id = aws_organizations_policy.deny_leave_organization.id
  target_id = data.aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_policy_attachment" "workloads_deny_iam" {
  policy_id = aws_organizations_policy.deny_iam_users.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "sandbox_deny_iam" {
  policy_id = aws_organizations_policy.deny_iam_users.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}

resource "aws_organizations_policy_attachment" "workloads_deny_security" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "infrastructure_deny_security" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = aws_organizations_organizational_unit.infrastructure.id
}

resource "aws_organizations_policy_attachment" "security_deny_security" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = aws_organizations_organizational_unit.security.id
}

resource "aws_organizations_policy_attachment" "sandbox_deny_security" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}

resource "aws_organizations_policy_attachment" "workloads_deny_regions" {
  policy_id = aws_organizations_policy.deny_non_approved_regions.id
  target_id = aws_organizations_organizational_unit.workloads.id
}
