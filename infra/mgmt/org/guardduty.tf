# E03-S007: Enable GuardDuty and delegate administration to security-audit account

# 1. Enable GuardDuty in the Management Account (Required to delegate)
resource "aws_guardduty_detector" "mgmt" {
  enable = true
}

# 2. Delegate GuardDuty Administration to the Security Audit Account
# Security Audit Account ID: 172134854767
resource "aws_guardduty_organization_admin_account" "security_audit" {
  admin_account_id = "172134854767"

  depends_on = [aws_guardduty_detector.mgmt]
}

# 3. Configure Organization-wide settings (Auto-enable for new members)
# Note: This resource is typically managed in the delegated admin account,
# but can be initialized here if the provider is configured for the member account.
# For now, we enable the organization configuration in the mgmt account to ensure
# new accounts are covered immediately upon creation.

resource "aws_guardduty_organization_configuration" "org" {
  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.mgmt.id

  # Enable S3 protection by default for the organization
  datasources {
    s3_logs {
      auto_enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = true
        }
      }
    }
  }
}
