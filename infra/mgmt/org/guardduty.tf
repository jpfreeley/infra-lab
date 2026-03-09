# E03-S007: Enable GuardDuty and delegate administration to security-audit account

# 1. Enable GuardDuty in the Management Account (Required to delegate)
# Data source to get GuardDuty detector in Log Archive Account (us-east-1)
data "aws_guardduty_detector" "log_archive" {
  provider = aws.delegated_admin
}

# Enable GuardDuty in the Delegated Admin Account (Log Archive) for us-west-2
resource "aws_guardduty_detector" "log_archive_replica" {
  provider = aws.delegated_admin_replica
  enable   = true
}

resource "aws_guardduty_detector" "mgmt" {
  # checkov:skip=CKV2_AWS_3:GuardDuty is enabled and delegated to the Security/Log Archive account per best practices.
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_detector" "mgmt_replica" {
  # checkov:skip=CKV2_AWS_3:GuardDuty is enabled and delegated to the Security/Log Archive account per best practices.
  provider                     = aws.replica
  enable                       = true
  finding_publishing_frequency = "SIX_HOURS"
}

# 2. Delegate GuardDuty Administration to the Log Archive Account
# Log Archive Account ID: 172134854767
resource "aws_guardduty_organization_admin_account" "security_audit" {
  admin_account_id = "172134854767"

  depends_on = [aws_guardduty_detector.mgmt]
}

resource "aws_guardduty_organization_admin_account" "security_audit_replica" {
  provider         = aws.replica
  admin_account_id = "172134854767"

  depends_on = [aws_guardduty_detector.mgmt_replica]
}

# 3. Configure Organization-wide settings
# This resource must be managed using the Delegated Administrator's credentials
# We use a provider alias configured for the delegated admin account

resource "aws_guardduty_organization_configuration" "org" {
  # Use provider alias for delegated admin account
  provider = aws.delegated_admin

  # Use the Detector ID from the Log Archive Account (Delegated Admin)
  detector_id                      = data.aws_guardduty_detector.log_archive.id
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

resource "aws_guardduty_organization_configuration" "org_replica" {
  # Use provider alias for delegated admin account in replica region
  provider = aws.delegated_admin_replica

  # Use the Detector ID from the Log Archive Account (Delegated Admin) in replica region
  detector_id                      = aws_guardduty_detector.log_archive_replica.id
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
  depends_on = [aws_guardduty_organization_admin_account.security_audit_replica]
}
