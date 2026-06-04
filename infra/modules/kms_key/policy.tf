####
# Standard KMS Key Policy Template - E03-S015
#
# Provides a standardized key policy that meets organization security requirements:
# 1. Root account always has full admin access (prevents lockout)
# 2. Key administrators can manage but not use the key
# 3. Key users can encrypt/decrypt but not manage
# 4. Optional service principals for AWS service integrations
# 5. Optional cross-account access for multi-account deployments
####

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "standard_key_policy" {
  # checkov:skip=CKV_AWS_111:KMS key policies require wildcard resource — it refers to the key itself
  # checkov:skip=CKV_AWS_356:KMS key policies require wildcard resource — it refers to the key itself
  # checkov:skip=CKV_AWS_109:Root principal requires full management permissions to prevent lockout
  # Statement 1: Root account full access (required to prevent lockout)
  statement {
    sid    = "EnableRootAccountFullAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Statement 2: Key administrators (manage lifecycle, not use)
  dynamic "statement" {
    for_each = length(var.key_administrator_arns) > 0 ? [1] : []
    content {
      sid    = "AllowKeyAdministration"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_administrator_arns
      }

      actions = [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion"
      ]
      resources = ["*"]
    }
  }

  # Statement 3: Key users (encrypt/decrypt only)
  dynamic "statement" {
    for_each = length(var.key_user_arns) > 0 ? [1] : []
    content {
      sid    = "AllowKeyUsage"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_user_arns
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
  }

  # Statement 4: Grant creation for key users
  dynamic "statement" {
    for_each = length(var.key_user_arns) > 0 ? [1] : []
    content {
      sid    = "AllowGrantsForKeyUsers"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_user_arns
      }

      actions = [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant"
      ]
      resources = ["*"]

      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }

  # Statement 5: AWS service principals
  dynamic "statement" {
    for_each = length(var.service_principal_arns) > 0 ? [1] : []
    content {
      sid    = "AllowServicePrincipalAccess"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = var.service_principal_arns
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
  }

  # Statement 6: Cross-account access
  dynamic "statement" {
    for_each = length(var.cross_account_arns) > 0 ? [1] : []
    content {
      sid    = "AllowCrossAccountAccess"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.cross_account_arns
      }

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
  }
}
