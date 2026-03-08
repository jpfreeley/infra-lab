# E03-S007: Enable GuardDuty and delegate administration to security-audit account

# 1. Enable GuardDuty in the Management Account (Required to delegate)
resource "aws_guardduty_detector" "mgmt" {
  enable = true
}

# 2. Delegate GuardDuty Administration to the Log Archive Account
# Log Archive Account ID: 172134854767
resource "aws_guardduty_organization_admin_account" "security_audit" {
  admin_account_id = "172134854767"

  depends_on = [aws_guardduty_detector.mgmt]
}

# 3. Configure Organization-wide settings
# This resource must be managed using the Delegated Administrator's credentials
# We use a provider alias configured for the delegated admin account

resource "aws_guardduty_organization_configuration" "org" {
  # Use provider alias for delegated admin account
  provider = aws.delegated_admin

  # Use the Detector ID from the Log Archive Account (Delegated Admin)
  detector_id                      = "80ce656eaede5e533ce9b198fe16f3cd"
  auto_enable_organization_members = "ALL"

  # Data sources configuration
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

  # Ensure delegation happens before trying to configure the org
  depends_on = [aws_guardduty_organization_admin_account.security_audit]
}
