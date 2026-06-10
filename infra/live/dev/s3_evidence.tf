# S3 Evidence Bucket
# Epic: E07 - Data Plane (Aurora + RDS Proxy + S3)
# Story: S005 - S3 evidence bucket per env with SSE-KMS + lifecycle

###############################################################################
# KMS Key for Evidence Bucket Encryption
###############################################################################

module "evidence_kms" {
  source = "../../modules/kms_key"

  alias               = "${local.name_prefix}-evidence"
  enable_key_rotation = true
}

###############################################################################
# Evidence Bucket (stores processing outputs, audit trails, reports)
###############################################################################

module "evidence_bucket" {
  source = "../../modules/s3_secure_bucket"

  name        = "${local.name_prefix}-evidence"
  kms_key_arn = module.evidence_kms.key_arn

  lifecycle_days = 90 # Dev evidence expires after 90 days
}
