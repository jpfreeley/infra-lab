# VPC Flow Logs - DISABLED for cost optimization
# Epic: E05 - Networking (Dual VPC per env)
# Story: S022 - Centralized VPC flow logs
#
# Re-enable when workloads are deployed. Each KMS key costs $1/mo.
# Uncomment below and set enable_flow_logs=true in vpc.tf.

# module "flow_logs_kms" {
#   source = "../../modules/kms_key"
#
#   alias               = "alias/infra-lab-flow-logs"
#   description         = "KMS key for VPC flow logs encryption"
#   enable_key_rotation = true
#
#   tags = local.common_tags
# }

# module "flow_logs_bucket" {
#   source = "../../modules/s3_secure_bucket"
#
#   name           = "infra-lab-flow-logs-551452024305"
#   kms_key_arn    = module.flow_logs_kms.key_arn
#   lifecycle_days = 90
# }
