# MemPalace KMS Key
# Encrypts EFS, CloudWatch Logs, and the bearer-token secret. Root-account
# full access (granted by default in the kms_key module's standard policy)
# is what lets the mempalace_server module's execution role decrypt the
# secret via its own IAM policy — no need to enumerate role ARNs here,
# which would otherwise create a circular dependency between this key and
# the module that consumes it.
#
# logs.<region>.amazonaws.com is the one AWS-documented hard requirement:
# CloudWatch Logs needs an explicit service-principal grant to use a CMK,
# unlike EFS/Secrets Manager which work off the root-account grant alone.

module "mempalace_kms" {
  source = "../../modules/kms_key"

  alias       = "alias/${local.name_prefix}"
  description = "MemPalace EFS, CloudWatch Logs, and bearer-token secret encryption"

  service_principal_arns = ["logs.${var.aws_region}.amazonaws.com"]

  tags = local.common_tags
}
