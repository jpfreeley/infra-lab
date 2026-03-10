# --- CloudTrail Consolidation Notes ---
# On 2026-03-10, it was identified that the account had two redundant Organization Trails:
# 1. aws-controltower-BaselineCloudTrail (Managed by Control Tower)
# 2. infra-lab-org-trail (Managed by this Terraform file)
#
# Both trails were capturing the same management events across all regions and accounts,
# leading to additional costs ($2.00 per 100,000 events for the second trail).
#
# Consolidation Steps Taken:
# - Verified that 'infra-lab-org-trail' is a Multi-Region Organization Trail.
# - Editted Control Tower Settings to DISABLE baseline trail (35m to update settings)
# - Stopped logging and deleted the redundant Control Tower baseline trail via CLI:
#   aws cloudtrail stop-logging --name aws-controltower-BaselineCloudTrail --profile infra-lab --region us-east-1
#   aws cloudtrail delete-trail --name aws-controltower-BaselineCloudTrail --profile infra-lab --region us-east-1
#
# Note: Control Tower may report 'Drift' in the console. To resolve this permanently,
# the CloudTrail baseline should be disabled in the Control Tower Landing Zone settings.

# --- KMS Keys ---

# 1. KMS Key for CloudTrail S3 Logs
resource "aws_kms_key" "cloudtrail" {
  description             = "KMS key for Organization-wide CloudTrail"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.cloudtrail_kms.json

  tags = {
    Name = "infra-lab-cloudtrail-org-key"
  }
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/cloudtrail-org"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# 2. KMS Key for CloudWatch Logs (CloudTrail Integration)
resource "aws_kms_key" "cloudwatch" {
  description             = "KMS key for CloudTrail CloudWatch Logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_cloudwatch.json

  tags = {
    Name = "infra-lab-cloudwatch-cloudtrail-key"
  }
}

resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/cloudwatch-cloudtrail"
  target_key_id = aws_kms_key.cloudwatch.key_id
}

# --- CloudWatch Logs Configuration ---

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/infra-lab-org-trail"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch.arn
}

resource "aws_iam_role" "cloudtrail_cloudwatch_role" {
  name = "infra-lab-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch_policy" {
  name = "infra-lab-cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

# --- CloudTrail Resource ---

resource "aws_cloudtrail" "org_trail" {
  # checkov:skip=CKV_AWS_252:SNS topic not required for this architectural stage
  name                          = "infra-lab-org-trail"
  s3_bucket_name                = "aws-controltower-logs-172134854767-us-east-1"
  s3_key_prefix                 = "o-hrzezrr7b1/AWSLogs"
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  # Reference the resource directly to satisfy Checkov CKV2_AWS_10
  # The :* suffix is required by the CloudTrail API
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch_role.arn

  depends_on = [
    aws_organizations_organization.org
  ]
}

# --- IAM Policy Documents (KMS) ---

# Policy for CloudWatch Logs KMS Key
data "aws_iam_policy_document" "kms_cloudwatch" {
  statement {
    sid    = "Allow CloudTrail to use the CloudWatch Logs KMS key"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]
    resources = ["*"] # Fixed Cycle
  }

  statement {
    # checkov:skip=CKV_AWS_111:Root principal requires full access to prevent lockout
    # checkov:skip=CKV_AWS_356:KMS policies require wildcard resource for the key itself
    # checkov:skip=CKV_AWS_109:Root principal requires management permissions
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::551452024305:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    # checkov:skip=CKV_AWS_356:KMS policies require wildcard resource for the key itself
    sid    = "Allow CloudWatch Logs to use the key"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
  }

  statement {
    # checkov:skip=CKV_AWS_356:KMS policies require wildcard resource for the key itself
    sid    = "Allow CloudTrail SLR to use the key"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::551452024305:role/aws-service-role/cloudtrail.amazonaws.com/AWSServiceRoleForCloudTrail"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]
    resources = ["*"] # Fixed Cycle
  }
}

# Policy for CloudTrail S3 KMS Key
data "aws_iam_policy_document" "cloudtrail_kms" {
  statement {
    # checkov:skip=CKV_AWS_111:Root principal requires full access to prevent lockout
    # checkov:skip=CKV_AWS_356:KMS policies require wildcard resource for the key itself
    # checkov:skip=CKV_AWS_109:Root principal requires management permissions
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::551452024305:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow CloudTrail to encrypt logs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"] # Fixed Cycle
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:551452024305:trail/*"]
    }
  }

  statement {
    sid    = "Allow Log Archive Account Access"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::172134854767:root"]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}
