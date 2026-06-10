# VPC Flow Logs S3 Bucket
# Epic: E05 - Networking (Dual VPC per env)
# Story: S022 - Centralized VPC flow logs

module "flow_logs_kms" {
  source = "../../modules/kms_key"

  alias               = "alias/infra-lab-prod-flow-logs"
  description         = "KMS key for prod VPC flow logs encryption"
  enable_key_rotation = true

  tags = local.common_tags
}

module "flow_logs_bucket" {
  source = "../../modules/s3_secure_bucket"

  name           = "infra-lab-prod-flow-logs-551452024305"
  kms_key_arn    = module.flow_logs_kms.key_arn
  lifecycle_days = 365 # Longer retention for prod
}
