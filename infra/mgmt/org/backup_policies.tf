####
# Organization Backup Policies - E03-S021
#
# Defines organization-wide backup policies that automatically protect
# critical resources across all member accounts. Backup policies use
# AWS Backup to create scheduled backups with defined retention periods.
#
# This policy targets resources tagged with Backup=true and creates
# daily backups with 35-day retention and monthly backups with 1-year retention.
####

resource "aws_organizations_policy" "backup_policy" {
  name        = "${local.project_name}-${local.environment}-backup-policy"
  description = "Organization-wide backup policy for critical resources with daily and monthly schedules."
  type        = "BACKUP_POLICY"

  content = jsonencode({
    plans = {
      infra-lab-org-backup-plan = {
        regions = {
          "@@assign" = ["us-east-1", "us-west-2"]
        }
        rules = {
          daily-backup = {
            lifecycle = {
              delete_after_days = {
                "@@assign" = "35"
              }
            }
            target_backup_vault_name = {
              "@@assign" = "Default"
            }
            schedule_expression = {
              "@@assign" = "cron(0 3 * * ? *)"
            }
            start_backup_window_minutes = {
              "@@assign" = "60"
            }
            complete_backup_window_minutes = {
              "@@assign" = "180"
            }
            enable_continuous_backup = {
              "@@assign" = false
            }
          }
          monthly-backup = {
            lifecycle = {
              delete_after_days = {
                "@@assign" = "365"
              }
            }
            target_backup_vault_name = {
              "@@assign" = "Default"
            }
            schedule_expression = {
              "@@assign" = "cron(0 3 1 * ? *)"
            }
            start_backup_window_minutes = {
              "@@assign" = "60"
            }
            complete_backup_window_minutes = {
              "@@assign" = "180"
            }
            enable_continuous_backup = {
              "@@assign" = false
            }
          }
        }
        selections = {
          tags = {
            backup-tagged-resources = {
              iam_role_arn = {
                "@@assign" = "arn:aws:iam::$account:role/aws-service-role/backup.amazonaws.com/AWSServiceRoleForBackup"
              }
              tag_key = {
                "@@assign" = "Backup"
              }
              tag_value = {
                "@@assign" = ["true"]
              }
            }
          }
        }
      }
    }
  })

  tags = merge(local.common_tags, { Story = "E03-S021" })
}

# Attach backup policy at the Organization root
resource "aws_organizations_policy_attachment" "backup_policy_root" {
  policy_id = aws_organizations_policy.backup_policy.id
  target_id = data.aws_organizations_organization.org.roots[0].id
}
