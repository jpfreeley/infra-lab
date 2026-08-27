# MemPalace Wake Lambda
# docs/adr/034-shared-mempalace-server.md, "MagNet Legal Instance" section.
#
# Lets MagNet Legal developers bring the shared mempalace stack back up
# themselves after idle-teardown, without needing GitHub or AWS access to
# infra-lab (that access boundary stays personal — see the ADR). Just
# triggers mempalace-toggle.yml's existing, already-tested "up" action via
# GitHub's REST API, the same as a human clicking "Run workflow."
#
# Deliberately deployed HERE (the management/dev account), not in
# infra/live/mempalace (the dedicated mempalace account) — that account's
# service-boundary SCP (infra/mgmt/org/mempalace_account.tf) explicitly
# denies everything except what the ECS Fargate deployment itself uses,
# lambda:* is not in its allow-list, on purpose ("no lambda/apigateway/
# dynamodb self-service API surface here"). Found this by actually reading
# the SCP before writing this file, not by assuming the mempalace account
# could host arbitrary services. This Lambda never touches ECS/ALB/EFS
# itself anyway — it only reads two Secrets Manager secrets and calls the
# public GitHub API — so it doesn't need to run inside that account's
# boundary at all. Same account rds_auto_stop.tf already lives in, same
# reasoning: small, single-purpose, management-account-hosted utility.
#
# Populate both secrets out-of-band after apply, same pattern as
# infra/live/mempalace/secrets.tf:
#
#   openssl rand -base64 32 | aws secretsmanager put-secret-value \
#     --secret-id infra-lab/mempalace-wake/wake-token \
#     --secret-string file:///dev/stdin --profile infra-lab --region us-east-1
#
#   # A fine-grained GitHub PAT, scope: Actions (read/write) on
#   # jpfreeley/infra-lab only — nothing broader.
#   echo -n "github_pat_..." | aws secretsmanager put-secret-value \
#     --secret-id infra-lab/mempalace-wake/github-pat \
#     --secret-string file:///dev/stdin --profile infra-lab --region us-east-1

###############################################################################
# Secrets
###############################################################################

# Both secrets use the existing secrets_manager module (../../modules/
# secrets_manager) rather than raw aws_secretsmanager_secret resources —
# matching infra/live/mempalace/secrets.tf's own pattern, and picking up
# that module's already-justified checkov:skip=CKV2_AWS_57 (auto-rotation
# not applicable to a manually-populated bearer token/PAT) for free
# instead of duplicating the same reasoning inline. No CMK
# (kms_key_arn left null): these gate "permission to click the up
# button," not mempalace content access itself, and the account's one
# existing CMK (module.evidence_kms in s3_evidence.tf) is purpose-built
# for an unrelated resource — not worth a second dedicated CMK's ~$1/mo
# for something this low-stakes.

module "mempalace_wake_token" {
  source = "../../modules/secrets_manager"

  secret_name   = "infra-lab/mempalace-wake/wake-token"
  description   = "Bearer token MagNet Legal developers use to call the wake endpoint. Value set out-of-band, never via Terraform."
  secret_string = null

  tags = merge(local.common_tags, {
    "Name" = "infra-lab-mempalace-wake-token"
  })
}

module "mempalace_wake_github_pat" {
  source = "../../modules/secrets_manager"

  secret_name   = "infra-lab/mempalace-wake/github-pat"
  description   = "Fine-grained GitHub PAT (actions:write on jpfreeley/infra-lab only) used server-side to trigger mempalace-toggle.yml. Never returned to callers. Value set out-of-band, never via Terraform."
  secret_string = null

  tags = merge(local.common_tags, {
    "Name" = "infra-lab-mempalace-wake-github-pat"
  })
}

###############################################################################
# Lambda Function
###############################################################################

data "archive_file" "mempalace_wake" {
  type        = "zip"
  source_file = "${path.module}/lambda/wake/handler.py"
  output_path = "${path.module}/lambda/wake/handler.zip"
}

resource "aws_lambda_function" "mempalace_wake" {
  # checkov:skip=CKV_AWS_115: "Reserved concurrency not needed — trivially low volume, a handful of manual wake requests at most"
  # checkov:skip=CKV_AWS_116: "DLQ not needed — this is synchronous (Function URL request/response), not event-driven; failures return directly to the caller"
  # checkov:skip=CKV_AWS_117: "VPC not needed — only calls Secrets Manager and the public GitHub API"
  # checkov:skip=CKV_AWS_173: "No sensitive env vars — secret ARNs are references, not the secret values themselves"
  # checkov:skip=CKV_AWS_272: "Code signing not required for internal Lambda"
  function_name = "${local.name_prefix}-mempalace-wake"
  description   = "Lets MagNet Legal devs trigger mempalace-toggle.yml (up) without infra-lab GitHub access"

  runtime  = "python3.12"
  handler  = "handler.handler"
  filename = data.archive_file.mempalace_wake.output_path
  timeout  = 15

  source_code_hash = data.archive_file.mempalace_wake.output_base64sha256

  role = aws_iam_role.mempalace_wake.arn

  environment {
    variables = {
      GITHUB_REPO           = "jpfreeley/infra-lab"
      WORKFLOW_FILE         = "mempalace-toggle.yml"
      WAKE_TOKEN_SECRET_ARN = module.mempalace_wake_token.secret_arn
      GITHUB_PAT_SECRET_ARN = module.mempalace_wake_github_pat.secret_arn
    }
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-mempalace-wake"
  })
}

resource "aws_lambda_function_url" "mempalace_wake" {
  # checkov:skip=CKV_AWS_258: "AuthType=NONE is deliberate, not an oversight — this endpoint exists specifically so MagNet Legal devs can call it WITHOUT any AWS credentials (that's the whole point, see the file header). Auth is a bearer-token check inside handler.py instead, checked with hmac.compare_digest against a value in Secrets Manager, distinct from mempalace's own token."
  function_name      = aws_lambda_function.mempalace_wake.function_name
  authorization_type = "NONE" # auth is the bearer-token check inside the handler itself

  cors {
    allow_methods = ["POST"]
    allow_origins = ["*"]
  }
}

# Function URLs with authorization_type=NONE still need this explicit
# permission, or every request 403s at the URL level before ever reaching
# the handler's own bearer-token check — a common gotcha, called out here
# so it isn't "discovered" again later.
resource "aws_lambda_permission" "mempalace_wake_url" {
  # checkov:skip=CKV_AWS_301: "Same deliberate public-URL design as aws_lambda_function_url.mempalace_wake above — the endpoint has to be reachable without AWS credentials by design; the handler's own bearer-token check is the real access control, not IAM."
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.mempalace_wake.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

###############################################################################
# IAM Role for Lambda
###############################################################################

resource "aws_iam_role" "mempalace_wake" {
  name = "${local.name_prefix}-mempalace-wake-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-mempalace-wake-role"
  })
}

resource "aws_iam_role_policy" "mempalace_wake" {
  name = "mempalace-wake-permissions"
  role = aws_iam_role.mempalace_wake.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWakeSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          module.mempalace_wake_token.secret_arn,
          module.mempalace_wake_github_pat.secret_arn,
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-mempalace-wake:*"
      }
    ]
  })
}
