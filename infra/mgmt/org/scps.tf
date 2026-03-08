resource "aws_organizations_policy" "deny_iam_users" {
  name        = "DenyIAMUserCreation"
  description = "Prevents the creation of IAM users and access keys to enforce IAM Identity Center usage."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyCreateIAMUser"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_organizations_policy" "deny_disabling_security_services" {
  name        = "DenyDisablingSecurityServices"
  description = "Prevents disabling or modifying critical security services (CloudTrail, GuardDuty, Config)."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDisablingSecurity"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
          "cloudtrail:UpdateTrail",
          "guardduty:DeleteDetector",
          "guardduty:ArchiveFindings",
          "guardduty:UpdateDetector",
          "config:DeleteConfigurationRecorder",
          "config:StopConfigurationRecorder",
          "config:DeleteDeliveryChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_organizations_policy" "deny_leaving_org" {
  name        = "DenyLeavingOrganization"
  description = "Prevents member accounts from leaving the AWS Organization."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyLeavingOrg"
        Effect = "Deny"
        Action = [
          "organizations:LeaveOrganization"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attachment to Root (Applies to all accounts except Management)
resource "aws_organizations_policy_attachment" "root_deny_leaving_org" {
  policy_id = aws_organizations_policy.deny_leaving_org.id
  target_id = aws_organizations_organization.org.roots[0].id
}

# Attachment to Workloads and Sandbox OUs (Enforce SSO)
resource "aws_organizations_policy_attachment" "workloads_deny_iam" {
  policy_id = aws_organizations_policy.deny_iam_users.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "sandbox_deny_iam" {
  policy_id = aws_organizations_policy.deny_iam_users.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}

# Attachment to all OUs for Security Services Protection
resource "aws_organizations_policy_attachment" "workloads_deny_disabling_security" {
  policy_id = aws_organizations_policy.deny_disabling_security_services.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "infrastructure_deny_disabling_security" {
  policy_id = aws_organizations_policy.deny_disabling_security_services.id
  target_id = aws_organizations_organizational_unit.infrastructure.id
}

resource "aws_organizations_policy_attachment" "security_deny_disabling_security" {
  policy_id = aws_organizations_policy.deny_disabling_security_services.id
  target_id = aws_organizations_organizational_unit.security.id
}
