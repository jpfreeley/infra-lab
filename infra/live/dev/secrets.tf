# Secrets Manager Configuration
# Epic: E09 - Secrets + PKI + mTLS
# Story: S001 - Bootstrap secrets and access policies
#
# Secrets are created with placeholder values. Actual values are injected
# externally (CLI or CI/CD) after initial terraform apply.

###############################################################################
# Application Secrets (consumed by ECS tasks via task execution role)
###############################################################################

# API database connection string (injected via RDS Proxy endpoint)
module "secret_api_db" {
  source = "../../modules/secrets_manager"

  secret_name = "${local.name_prefix}/api/database-url"
  description = "API service database connection string"

  # Placeholder — real value set externally after Aurora + Proxy deployment
  secret_string = jsonencode({
    host     = "placeholder.cluster-xxxxx.us-east-1.rds.amazonaws.com"
    port     = 5432
    dbname   = "control"
    username = "app_rw"
    password = "CHANGE_ME"
  })

  tags = local.common_tags
}

# Worker database connection string
module "secret_worker_db" {
  source = "../../modules/secrets_manager"

  secret_name = "${local.name_prefix}/worker/database-url"
  description = "Worker service database connection string"

  secret_string = jsonencode({
    host     = "placeholder.cluster-xxxxx.us-east-1.rds.amazonaws.com"
    port     = 5432
    dbname   = "execution"
    username = "app_rw"
    password = "CHANGE_ME"
  })

  tags = local.common_tags
}

# Shared application secrets (API keys, tokens, etc.)
module "secret_app_config" {
  source = "../../modules/secrets_manager"

  secret_name = "${local.name_prefix}/app/config"
  description = "Shared application configuration secrets"

  secret_string = jsonencode({
    jwt_signing_key = "CHANGE_ME"
    webhook_secret  = "CHANGE_ME"
  })

  tags = local.common_tags
}
