# KMS Key Module
# Epic: E02 - Terraform Foundations + State
# Story: S004 - Create Terraform module interface: kms_key

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  policy                  = var.policy != null ? var.policy : (var.use_standard_policy ? data.aws_iam_policy_document.standard_key_policy.json : null)

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = var.alias
  target_key_id = aws_kms_key.this.key_id
}
