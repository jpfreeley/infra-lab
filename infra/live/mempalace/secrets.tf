# MemPalace Bearer Token Secret
#
# Terraform creates the secret SHELL only — secret_string = null means this
# module never sees, stores, or manages the actual token value (the
# secrets_manager module's own documented pattern: `lifecycle.ignore_changes
# = [secret_string]` after first create). Populate the real value
# out-of-band, after apply:
#
#   openssl rand -base64 32 | aws secretsmanager put-secret-value \
#     --secret-id ${local.name_prefix}/mempalace/mcp-http-token \
#     --secret-string file:///dev/stdin --profile infra-lab \
#     --region us-east-1
#
# (assume into the mempalace account first — this profile flag alone isn't
# enough once the account exists; see providers.tf)
#
# Never put the token in a .tfvars file, a variable default, or this repo.

module "mempalace_token" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/mempalace/mcp-http-token"
  description   = "MEMPALACE_MCP_HTTP_TOKEN — bearer token for mempalace serve. Value set out-of-band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.mempalace_kms.key_arn

  tags = local.common_tags
}

# MagNet Legal instance's own bearer token — deliberately a separate
# secret, never the same value as mempalace_token above. Same out-of-band
# population pattern:
#
#   openssl rand -base64 32 | aws secretsmanager put-secret-value \
#     --secret-id ${local.name_prefix}/mempalace-magnetlegal/mcp-http-token \
#     --secret-string file:///dev/stdin --profile infra-lab \
#     --region us-east-1
module "mempalace_magnetlegal_token" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/mempalace-magnetlegal/mcp-http-token"
  description   = "MEMPALACE_MCP_HTTP_TOKEN — bearer token for the MagNet Legal mempalace instance. Value set out-of-band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.mempalace_kms.key_arn

  tags = local.common_tags
}
