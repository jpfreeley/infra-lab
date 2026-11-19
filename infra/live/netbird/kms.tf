# NetBird KMS Key
# Encrypts EFS, CloudWatch Logs, and the four Secrets Manager entries. Same
# pattern as mempalace_kms: the root-account grant in the kms_key module's
# standard policy lets the module's execution role decrypt via its own IAM
# policy; CloudWatch Logs needs the explicit service-principal grant.

module "netbird_kms" {
  source = "../../modules/kms_key"

  alias       = "alias/${local.name_prefix}"
  description = "NetBird EFS, CloudWatch Logs, and secrets encryption"

  service_principal_arns = ["logs.${var.aws_region}.amazonaws.com"]

  tags = local.common_tags
}
