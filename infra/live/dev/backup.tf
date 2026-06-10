# AWS Backup Configuration
# Epic: E12 - Reliability + Ops + Compliance
# Story: S001 - Backups: AWS Backup policies for RDS
#
# Note: Backup vault + plan created but NOT assigned to Aurora clusters in dev
# (clusters are frequently stopped for cost optimization — backup would fail).
# Assignment happens in prod via backup selection with tag-based targeting.

###############################################################################
# Backup Vault
###############################################################################

resource "aws_backup_vault" "this" {
  # checkov:skip=CKV_AWS_166: "Vault encryption uses default aws/backup key in dev; CMK in prod"
  name = "${local.name_prefix}-backup-vault"

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-backup-vault"
  })
}

###############################################################################
# Backup Plan (Daily + Monthly)
###############################################################################

resource "aws_backup_plan" "this" {
  name = "${local.name_prefix}-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 3 * * ? *)" # 3 AM UTC daily

    lifecycle {
      delete_after = 7 # 7-day retention in dev
    }

    recovery_point_tags = local.common_tags
  }

  rule {
    rule_name         = "monthly-backup"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 4 1 * ? *)" # 4 AM UTC on 1st of month

    lifecycle {
      delete_after = 35 # ~1 month retention in dev (365 in prod)
    }

    recovery_point_tags = local.common_tags
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-backup-plan"
  })
}

###############################################################################
# Backup IAM Role
###############################################################################

resource "aws_iam_role" "backup" {
  name = "${local.name_prefix}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-backup-role"
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

###############################################################################
# Backup Selection (tag-based — targets resources with Backup=true tag)
# Disabled in dev since Aurora clusters are frequently stopped.
# Enable by uncommenting and adding Backup=true tag to Aurora resources.
###############################################################################

# resource "aws_backup_selection" "rds" {
#   name         = "${local.name_prefix}-rds-selection"
#   plan_id      = aws_backup_plan.this.id
#   iam_role_arn = aws_iam_role.backup.arn
#
#   selection_tag {
#     type  = "STRINGEQUALS"
#     key   = "Backup"
#     value = "true"
#   }
# }
