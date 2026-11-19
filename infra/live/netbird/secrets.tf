# NetBird Secrets
#
# Terraform creates the secret SHELLS only (secret_string = null). Values
# are written out of band, and all four must exist before the ECS service
# first starts, or the task fails to launch. Assume into the NetBird
# account first (OrganizationAccountAccessRole), then:
#
#   # Relay auth secret (padding stripped, as upstream does)
#   openssl rand -base64 32 | tr -d '=' | aws secretsmanager put-secret-value \
#     --secret-id infra-lab-netbird/netbird/auth-secret --secret-string file:///dev/stdin
#
#   # Datastore encryption key (keep the padding)
#   openssl rand -base64 32 | aws secretsmanager put-secret-value \
#     --secret-id infra-lab-netbird/netbird/store-encryption-key --secret-string file:///dev/stdin
#
#   # Embedded IdP session cookie key
#   openssl rand -base64 32 | aws secretsmanager put-secret-value \
#     --secret-id infra-lab-netbird/netbird/session-cookie-key --secret-string file:///dev/stdin
#
#   # Initial owner, JSON, hex password (no YAML escaping needed)
#   python3 -c 'import json,secrets,sys; print(json.dumps({"email": sys.argv[1], "password": secrets.token_hex(24)}))' \
#     "<owner-email>" | aws secretsmanager put-secret-value \
#     --secret-id infra-lab-netbird/netbird/owner --secret-string file:///dev/stdin
#
# Never put any of these values in a .tfvars file, a variable default, or
# this repo.

module "netbird_auth_secret" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/netbird/auth-secret"
  description   = "NetBird relay auth secret (NB_AUTH_SECRET). Value set out of band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.netbird_kms.key_arn

  tags = local.common_tags
}

# The one value whose loss destroys data: without it the existing SQLite
# store is unreadable. Maximum recovery window, and never in a teardown
# target list.
module "netbird_store_key" {
  source = "../../modules/secrets_manager"

  secret_name             = "${local.name_prefix}/netbird/store-encryption-key"
  description             = "NetBird datastore encryption key (NB_STORE_ENCRYPTION_KEY). Losing it makes the database unreadable. Value set out of band, never via Terraform."
  secret_string           = null
  kms_key_arn             = module.netbird_kms.key_arn
  recovery_window_in_days = 30

  tags = local.common_tags
}

module "netbird_cookie_key" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/netbird/session-cookie-key"
  description   = "NetBird embedded IdP session cookie key (NB_IDP_SESSION_COOKIE_ENCRYPTION_KEY). Value set out of band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.netbird_kms.key_arn

  tags = local.common_tags
}

module "netbird_owner" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/netbird/owner"
  description   = "NetBird initial owner account, JSON {email, password}. Seeds auth.owner at first start. Value set out of band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.netbird_kms.key_arn

  tags = local.common_tags
}
