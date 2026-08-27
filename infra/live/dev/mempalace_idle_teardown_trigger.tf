# MemPalace Idle-Teardown Reliable Trigger
#
# mempalace-idle-teardown.yml's own `schedule: cron("*/15 * * * *")`
# trigger is GitHub's best-effort scheduler, with no SLA — observed gaps
# as large as ~4 hours during periods of platform load (2026-08-27),
# which meaningfully undermines a workflow whose whole point is catching
# an idle stack within roughly 90 minutes and tearing it down for cost
# control. This adds a second, independent trigger path with a real SLA:
# an EventBridge Scheduler rate(15 minutes) schedule invoking a small
# Lambda that calls the exact same workflow via GitHub's REST API, the
# same way GitHub's own cron trigger would. It doesn't reimplement any
# teardown logic — both paths dispatch the same, already-tested
# workflow. Runs alongside the existing cron trigger in the workflow
# file, not instead of it, so it isn't a single point of failure either.
#
# Deployed HERE (management/dev account), same reasoning as the sibling
# wake Lambda in this file's directory: the mempalace account's
# service-boundary SCP (infra/mgmt/org/mempalace_account.tf) explicitly
# denies events:* alongside lambda:*, so this can't live there anyway.
#
# Deliberately reuses the wake Lambda's existing GitHub PAT secret
# (module.mempalace_wake_github_pat in mempalace_wake_lambda.tf, scope:
# actions:write on jpfreeley/infra-lab only) rather than creating a
# second credential with the same scope — no new secret to populate or
# rotate.
#
# Deliberately NOT built as an EventBridge API destination calling
# GitHub directly (the simpler-looking option, no Lambda needed): that
# resource type (aws_cloudwatch_event_connection) requires the real PAT
# value to be set on the connection through Terraform, putting a live
# credential into Terraform state — a real regression from this repo's
# established pattern everywhere else (secret_string = null, value only
# ever set out-of-band, see mempalace_wake_lambda.tf's own header). A
# small Lambda that fetches the PAT from Secrets Manager at invoke time,
# matching the wake Lambda's own pattern exactly, keeps that guarantee
# intact at the cost of one extra small resource.

###############################################################################
# Lambda Function
###############################################################################

data "archive_file" "mempalace_idle_teardown_trigger" {
  type        = "zip"
  source_file = "${path.module}/lambda/idle_teardown_trigger/handler.py"
  output_path = "${path.module}/lambda/idle_teardown_trigger/handler.zip"
}

resource "aws_lambda_function" "mempalace_idle_teardown_trigger" {
  # checkov:skip=CKV_AWS_115: "Reserved concurrency not needed — invoked at most once per 15 minutes by a single EventBridge schedule"
  # checkov:skip=CKV_AWS_116: "DLQ not needed — synchronous invocation from EventBridge Scheduler, and the handler re-raises on failure so it surfaces directly in CloudWatch/Lambda error metrics instead of silently retrying into a queue"
  # checkov:skip=CKV_AWS_117: "VPC not needed — only calls Secrets Manager and the public GitHub API"
  # checkov:skip=CKV_AWS_173: "No sensitive env vars — the secret ARN is a reference, not the secret value itself"
  # checkov:skip=CKV_AWS_272: "Code signing not required for internal Lambda"
  function_name = "${local.name_prefix}-mempalace-idle-teardown-trigger"
  description   = "Reliable EventBridge-scheduled trigger for mempalace-idle-teardown.yml, alongside its own best-effort GitHub cron trigger"

  runtime  = "python3.12"
  handler  = "handler.handler"
  filename = data.archive_file.mempalace_idle_teardown_trigger.output_path
  timeout  = 15

  source_code_hash = data.archive_file.mempalace_idle_teardown_trigger.output_base64sha256

  role = aws_iam_role.mempalace_idle_teardown_trigger.arn

  environment {
    variables = {
      GITHUB_REPO           = "jpfreeley/infra-lab"
      WORKFLOW_FILE         = "mempalace-idle-teardown.yml"
      GITHUB_PAT_SECRET_ARN = module.mempalace_wake_github_pat.secret_arn
    }
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-mempalace-idle-teardown-trigger"
  })
}

###############################################################################
# IAM Role for Lambda (execution role — reads the shared PAT secret, writes logs)
###############################################################################

resource "aws_iam_role" "mempalace_idle_teardown_trigger" {
  name = "${local.name_prefix}-mempalace-idle-teardown-trigger-role"

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
    "Name" = "${local.name_prefix}-mempalace-idle-teardown-trigger-role"
  })
}

resource "aws_iam_role_policy" "mempalace_idle_teardown_trigger" {
  name = "mempalace-idle-teardown-trigger-permissions"
  role = aws_iam_role.mempalace_idle_teardown_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSharedGithubPat"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          module.mempalace_wake_github_pat.secret_arn
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
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-mempalace-idle-teardown-trigger:*"
      }
    ]
  })
}

###############################################################################
# EventBridge Scheduler — the actual reliable rate(15 minutes) trigger
###############################################################################

resource "aws_scheduler_schedule" "mempalace_idle_teardown_trigger" {
  # checkov:skip=CKV_AWS_297: "AWS-managed key is proportionate here, same reasoning as the sibling secrets in mempalace_wake_lambda.tf — this schedule carries no sensitive payload (just a fire-and-forget workflow-dispatch trigger), not worth a dedicated CMK's ~$1/mo for something this low-stakes"
  name       = "${local.name_prefix}-mempalace-idle-teardown-trigger"
  group_name = "default"

  # No jitter tolerance needed — this isn't invoking a scarce/rate-limited
  # resource, and the whole point is running as close to every 15 minutes
  # as EventBridge Scheduler's own SLA allows.
  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(15 minutes)"

  target {
    arn      = aws_lambda_function.mempalace_idle_teardown_trigger.arn
    role_arn = aws_iam_role.mempalace_idle_teardown_scheduler.arn

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 300 # a retry more than 5 min stale isn't worth it — the next 15-min tick will fire soon anyway
    }
  }
}

###############################################################################
# IAM Role for EventBridge Scheduler (permission to invoke the Lambda above)
###############################################################################

resource "aws_iam_role" "mempalace_idle_teardown_scheduler" {
  name = "${local.name_prefix}-mempalace-idle-teardown-scheduler-role"

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
    "Name" = "${local.name_prefix}-mempalace-idle-teardown-scheduler-role"
  })
}

resource "aws_iam_role_policy" "mempalace_idle_teardown_scheduler" {
  name = "mempalace-idle-teardown-scheduler-invoke"
  role = aws_iam_role.mempalace_idle_teardown_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeIdleTeardownTriggerLambda"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.mempalace_idle_teardown_trigger.arn
      }
    ]
  })
}
