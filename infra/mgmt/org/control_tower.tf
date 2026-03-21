resource "aws_controltower_landing_zone" "main" {
  version = "4.0"

  manifest_json = jsonencode({
    governedRegions = ["us-east-2", "eu-west-1", "us-east-1", "us-west-2"]
    accessManagement = {
      enabled = true
    }
    securityRoles = {
      accountId = "881413600100"
      enabled   = true
    }
    backup = {
      enabled = false
    }
    config = {
      accountId = "881413600100"
      enabled   = true
      configurations = {
        loggingBucket = {
          retentionDays = 365 # Integer, no quotes
        }
        accessLoggingBucket = {
          retentionDays = 3650 # Integer, no quotes
        }
      }
    }
    centralizedLogging = {
      accountId = "172134854767"
      enabled   = true
      configurations = {
        loggingBucket = {
          retentionDays = 365 # Integer, no quotes
        }
        accessLoggingBucket = {
          retentionDays = 3650 # Integer, no quotes
        }
      }
    }
  })
}
