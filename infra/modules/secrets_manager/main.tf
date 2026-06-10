# Secrets Manager Module
# Epic: E09 - Secrets + PKI + mTLS
# Story: S001 - Bootstrap secrets and access policies

###############################################################################
# Secret
###############################################################################

resource "aws_secretsmanager_secret" "this" {
  # checkov:skip=CKV2_AWS_57: "Auto-rotation configured separately per secret type"
  name        = var.secret_name
  description = var.description
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    "Name"      = var.secret_name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Secret Value (initial, ignored after first create)
###############################################################################

resource "aws_secretsmanager_secret_version" "this" {
  count = var.secret_string != null ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.secret_string

  lifecycle {
    ignore_changes = [secret_string] # Value managed externally after bootstrap
  }
}

###############################################################################
# Resource Policy (controls who can read this secret)
###############################################################################

resource "aws_secretsmanager_secret_policy" "this" {
  count = var.policy_json != null ? 1 : 0

  secret_arn = aws_secretsmanager_secret.this.arn
  policy     = var.policy_json
}

###############################################################################
# Rotation (optional)
###############################################################################

resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.rotation_lambda_arn != null ? 1 : 0

  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}
