# KMS Key for Organization-wide CloudTrail
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

# Organization CloudTrail
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

  depends_on = [
    aws_organizations_organization.org
  ]
}

# KMS Policy to allow CloudTrail service to use the key
data "aws_iam_policy_document" "cloudtrail_kms" {
  # 1. Allow Management Account Root (Full Access)
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

  # 2. Allow CloudTrail Service to Encrypt
  statement {
    # checkov:skip=CKV_AWS_356:KMS policies require wildcard resource for the key itself
    sid    = "Allow CloudTrail to encrypt logs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:551452024305:trail/*"]
    }
  }

  # 3. Allow Log-Archive Account to Describe/Decrypt (Required for cross-account S3 delivery)
  statement {
    # checkov:skip=CKV_AWS_356:KMS policies require wildcard resource for the key itself
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
