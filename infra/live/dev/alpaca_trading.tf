# Scheduled Autonomous Paper Trading Runner
#
# EventBridge Scheduler (America/New_York, weekdays) invokes a Lambda that runs
# one wakeup of a model-driven paper trading agent against an Alpaca PAPER
# account, calling Claude through Bedrock. Design notes:
#
# - Nothing sensitive lives in this repo. The runner reads its strategy text,
#   prompts and numeric limits at runtime from a private S3 config prefix, and
#   the schedule times come from a gitignored tfvars file
#   (var.alpaca_trading_schedule has no default, so applying without it creates
#   no schedules).
# - Secrets (Alpaca paper keys, ntfy topic) are created empty and populated
#   out-of-band, matching this repo's secret_string = null pattern.
# - The runner does nothing unless control/enabled.json exists in the state
#   bucket and today falls inside its start/end dates, so the schedules are
#   inert by default and the whole thing expires on its own.
# - Deployed here (management/dev account), like the other Lambdas in this
#   directory, because the mempalace account's SCP denies lambda:* and events:*.

variable "alpaca_trading_schedule" {
  description = "Slot number => New York wall-clock time. No default: supplied by a gitignored tfvars file."
  type = map(object({
    hour   = number
    minute = number
  }))
  default = {}
}

variable "alpaca_trading_extra_strategies" {
  description = "Additional strategy ids run by the same Lambda, each with its own credentials secret and schedules. Supplied by a gitignored tfvars file. The default strategy needs no entry."
  type        = set(string)
  default     = []
}

variable "alpaca_trading_model_id" {
  description = "Bedrock inference profile ID the runner invokes"
  type        = string
  default     = "global.anthropic.claude-opus-5-5"
}

variable "alpaca_trading_input_usd_per_mtok" {
  description = "Input token price (USD per million) used for the per-run cost cap"
  type        = number
  default     = 4
}

variable "alpaca_trading_output_usd_per_mtok" {
  description = "Output token price (USD per million) used for the per-run cost cap"
  type        = number
  default     = 20
}

###############################################################################
# State bucket (config, handoff, journal, evidence) with a dedicated KMS key
###############################################################################

module "alpaca_trading_kms" {
  source = "../../modules/kms_key"

  alias               = "alias/${local.name_prefix}-alpaca-trading"
  enable_key_rotation = true
}

module "alpaca_trading_bucket" {
  source = "../../modules/s3_secure_bucket"

  name        = "${local.name_prefix}-alpaca-trading"
  kms_key_arn = module.alpaca_trading_kms.key_arn

  lifecycle_days = 90
}

###############################################################################
# Secrets (empty; values set out-of-band)
###############################################################################

module "alpaca_trading_alpaca_keys" {
  source = "../../modules/secrets_manager"

  secret_name   = "infra-lab/alpaca-trading/alpaca-paper-keys"
  description   = "JSON {key_id, secret_key} for the Alpaca PAPER trading account. Value set out-of-band, never via Terraform."
  secret_string = null

  tags = merge(local.common_tags, {
    "Name" = "infra-lab-alpaca-trading-alpaca-paper-keys"
  })
}

module "alpaca_trading_extra_keys" {
  source   = "../../modules/secrets_manager"
  for_each = var.alpaca_trading_extra_strategies

  secret_name   = "infra-lab/alpaca-trading/alpaca-paper-keys-${each.key}"
  description   = "JSON {key_id, secret_key} for the Alpaca PAPER account of strategy ${each.key}. Value set out-of-band, never via Terraform."
  secret_string = null

  tags = merge(local.common_tags, {
    "Name" = "infra-lab-alpaca-trading-alpaca-paper-keys-${each.key}"
  })
}

module "alpaca_trading_ntfy_topic" {
  source = "../../modules/secrets_manager"

  secret_name   = "infra-lab/alpaca-trading/ntfy-topic"
  description   = "ntfy.sh topic name for trading notifications. Value set out-of-band, never via Terraform."
  secret_string = null

  tags = merge(local.common_tags, {
    "Name" = "infra-lab-alpaca-trading-ntfy-topic"
  })
}

###############################################################################
# Lambda
###############################################################################

data "archive_file" "alpaca_trader" {
  type        = "zip"
  output_path = "${path.module}/lambda/alpaca_trader/handler.zip"

  # Package only the runner modules (tests are not shipped).
  dynamic "source" {
    for_each = fileset("${path.module}/lambda/alpaca_trader", "*.py")
    content {
      content  = file("${path.module}/lambda/alpaca_trader/${source.value}")
      filename = source.value
    }
  }
}

resource "aws_cloudwatch_log_group" "alpaca_trader" {
  # checkov:skip=CKV_AWS_338: "30-day retention is proportionate for a paper-trading challenge; the durable record is the journal in S3, not CloudWatch"
  # checkov:skip=CKV_AWS_158: "AWS-managed log encryption is proportionate; logs contain no secrets (values are fetched at runtime and never logged)"
  name              = "/aws/lambda/${local.name_prefix}-alpaca-trader"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-alpaca-trader-logs"
  })
}

resource "aws_lambda_function" "alpaca_trader" {
  # checkov:skip=CKV_AWS_115: "Concurrency is controlled by an S3 run lock, and reserved concurrency can violate the account's unreserved-minimum on small accounts"
  # checkov:skip=CKV_AWS_116: "DLQ not needed: the handler catches every failure, alerts the phone and returns normally; the scheduler does not retry"
  # checkov:skip=CKV_AWS_117: "VPC not needed: only calls Secrets Manager, S3, Bedrock, Alpaca and ntfy over public endpoints"
  # checkov:skip=CKV_AWS_173: "No sensitive env vars: secret ARNs are references, values are fetched at runtime"
  # checkov:skip=CKV_AWS_272: "Code signing not required for an internal Lambda"
  function_name = "${local.name_prefix}-alpaca-trader"
  description   = "Scheduled paper trading runner (Alpaca paper account, Claude on Bedrock)"

  runtime  = "python3.12"
  handler  = "handler.handler"
  filename = data.archive_file.alpaca_trader.output_path
  timeout  = 600

  memory_size      = 256
  source_code_hash = data.archive_file.alpaca_trader.output_base64sha256

  role = aws_iam_role.alpaca_trader.arn

  environment {
    variables = {
      STATE_BUCKET              = module.alpaca_trading_bucket.bucket_id
      ALPACA_SECRET_ARN         = module.alpaca_trading_alpaca_keys.secret_arn
      ALPACA_SECRET_ARNS        = jsonencode({ for k, m in module.alpaca_trading_extra_keys : k => m.secret_arn })
      NTFY_SECRET_ARN           = module.alpaca_trading_ntfy_topic.secret_arn
      MODEL_ID                  = var.alpaca_trading_model_id
      MODEL_INPUT_USD_PER_MTOK  = tostring(var.alpaca_trading_input_usd_per_mtok)
      MODEL_OUTPUT_USD_PER_MTOK = tostring(var.alpaca_trading_output_usd_per_mtok)
    }
  }

  depends_on = [aws_cloudwatch_log_group.alpaca_trader]

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-alpaca-trader"
  })
}

###############################################################################
# IAM for the Lambda
###############################################################################

resource "aws_iam_role" "alpaca_trader" {
  name = "${local.name_prefix}-alpaca-trader-role"

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
    "Name" = "${local.name_prefix}-alpaca-trader-role"
  })
}

resource "aws_iam_role_policy" "alpaca_trader" {
  name = "alpaca-trader-permissions"
  role = aws_iam_role.alpaca_trader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucketObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${module.alpaca_trading_bucket.bucket_arn}/*"
      },
      {
        Sid      = "StateBucketList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = module.alpaca_trading_bucket.bucket_arn
      },
      {
        Sid    = "StateBucketKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = module.alpaca_trading_kms.key_arn
      },
      {
        Sid    = "ReadTradingSecrets"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = concat(
          [
            module.alpaca_trading_alpaca_keys.secret_arn,
            module.alpaca_trading_ntfy_topic.secret_arn
          ],
          [for m in module.alpaca_trading_extra_keys : m.secret_arn]
        )
      },
      {
        Sid    = "InvokeClaudeOnBedrock"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/anthropic.*",
          "arn:aws:bedrock:${var.aws_region}:*:inference-profile/*anthropic.*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.alpaca_trader.arn}:*"
      }
    ]
  })
}

###############################################################################
# EventBridge Scheduler (one schedule per slot, weekdays, New York time)
###############################################################################

resource "aws_scheduler_schedule" "alpaca_trader" {
  # checkov:skip=CKV_AWS_297: "AWS-managed key is proportionate: the schedule payload is just a slot number, nothing sensitive"
  for_each = var.alpaca_trading_schedule

  name       = "${local.name_prefix}-alpaca-trader-slot-${each.key}"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(${each.value.minute} ${each.value.hour} ? * MON-FRI *)"
  schedule_expression_timezone = "America/New_York"

  target {
    arn      = aws_lambda_function.alpaca_trader.arn
    role_arn = aws_iam_role.alpaca_trader_scheduler.arn
    input    = jsonencode({ slot = tonumber(each.key) })

    # No retries: a retried run could act twice. The handler alerts on failure.
    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 60
    }
  }
}

# One schedule per (extra strategy, slot), same times as the default strategy.
resource "aws_scheduler_schedule" "alpaca_trader_extra" {
  # checkov:skip=CKV_AWS_297: "AWS-managed key is proportionate: the schedule payload is just a slot number and strategy id, nothing sensitive"
  for_each = {
    for pair in setproduct(var.alpaca_trading_extra_strategies, keys(var.alpaca_trading_schedule)) :
    "${pair[0]}-${pair[1]}" => { strategy = pair[0], slot = pair[1] }
  }

  name       = "${local.name_prefix}-alpaca-trader-${each.value.strategy}-slot-${each.value.slot}"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(${var.alpaca_trading_schedule[each.value.slot].minute} ${var.alpaca_trading_schedule[each.value.slot].hour} ? * MON-FRI *)"
  schedule_expression_timezone = "America/New_York"

  target {
    arn      = aws_lambda_function.alpaca_trader.arn
    role_arn = aws_iam_role.alpaca_trader_scheduler.arn
    input    = jsonencode({ slot = tonumber(each.value.slot), strategy = each.value.strategy })

    # No retries: a retried run could act twice. The handler alerts on failure.
    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 60
    }
  }
}

resource "aws_iam_role" "alpaca_trader_scheduler" {
  name = "${local.name_prefix}-alpaca-trader-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-alpaca-trader-scheduler-role"
  })
}

resource "aws_iam_role_policy" "alpaca_trader_scheduler" {
  name = "alpaca-trader-scheduler-invoke"
  role = aws_iam_role.alpaca_trader_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeTraderLambda"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.alpaca_trader.arn
      }
    ]
  })
}

output "alpaca_trading_bucket" {
  description = "State bucket for the paper trading runner"
  value       = module.alpaca_trading_bucket.bucket_id
}

output "alpaca_trader_function" {
  description = "Paper trading runner Lambda name"
  value       = aws_lambda_function.alpaca_trader.function_name
}
