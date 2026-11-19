# NetBird Lease-Teardown Trigger (primary clock)
# ADR-037: Self-Hosted NetBird Server in a Dedicated Account, Torn Down When Idle
#
# EventBridge Scheduler rate(15 minutes) invokes a small Lambda that
# dispatches .github/workflows/netbird-lease-teardown.yml through the GitHub
# API. Unlike MemPalace, where GitHub cron came first and this kind of
# trigger was added later as a backup, ADR-037 makes EventBridge the primary
# clock and the workflow's own GitHub cron the fallback.
#
# Same code as the MemPalace trigger (lambda/idle_teardown_trigger/
# handler.py reads the target workflow from WORKFLOW_FILE), so this is new
# configuration, not new code. Reuses the same archive and the same GitHub
# token secret (module.mempalace_wake_github_pat, actions:write on
# jpfreeley/infra-lab only), so there is nothing new to populate.
#
# Lives in this (management) account because the NetBird account's SCP
# denies lambda and events by design (infra/mgmt/org/netbird_account.tf).
#
# Not yet built: an alarm on this Lambda's Errors metric (ADR-037). The
# dev stack has no alarm topic with a subscriber, so an alarm would alert
# no one; adding an alert path is a separate follow-up. Until then, a
# broken token shows up as teardowns arriving late via the GitHub cron
# fallback, and as errors in this Lambda's log group.

resource "aws_lambda_function" "netbird_lease_teardown_trigger" {
  # checkov:skip=CKV_AWS_115: "Reserved concurrency not needed: invoked at most once per 15 minutes by a single schedule"
  # checkov:skip=CKV_AWS_116: "DLQ not needed: synchronous invocation from EventBridge Scheduler; the handler re-raises so failures show in Lambda error metrics"
  # checkov:skip=CKV_AWS_117: "VPC not needed: only calls Secrets Manager and the public GitHub API"
  # checkov:skip=CKV_AWS_173: "No sensitive env vars: the secret ARN is a reference, not the value"
  # checkov:skip=CKV_AWS_272: "Code signing not required for internal Lambda"
  function_name = "${local.name_prefix}-netbird-lease-teardown-trigger"
  description   = "EventBridge-scheduled primary trigger for netbird-lease-teardown.yml (GitHub cron is the fallback)"

  runtime  = "python3.12"
  handler  = "handler.handler"
  filename = data.archive_file.mempalace_idle_teardown_trigger.output_path
  timeout  = 15

  source_code_hash = data.archive_file.mempalace_idle_teardown_trigger.output_base64sha256

  role = aws_iam_role.netbird_lease_teardown_trigger.arn

  environment {
    variables = {
      GITHUB_REPO           = "jpfreeley/infra-lab"
      WORKFLOW_FILE         = "netbird-lease-teardown.yml"
      GITHUB_PAT_SECRET_ARN = module.mempalace_wake_github_pat.secret_arn
    }
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-netbird-lease-teardown-trigger"
  })
}

resource "aws_iam_role" "netbird_lease_teardown_trigger" {
  name = "${local.name_prefix}-netbird-lease-teardown-trigger-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-netbird-lease-teardown-trigger-role"
  })
}

resource "aws_iam_role_policy" "netbird_lease_teardown_trigger" {
  name = "netbird-lease-teardown-trigger-permissions"
  role = aws_iam_role.netbird_lease_teardown_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSharedGithubPat"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [module.mempalace_wake_github_pat.secret_arn]
      },
      {
        Sid      = "CloudWatchLogsGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup"]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-netbird-lease-teardown-trigger"
      },
      {
        Sid      = "CloudWatchLogsStream"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-netbird-lease-teardown-trigger:*"
      }
    ]
  })
}

resource "aws_scheduler_schedule" "netbird_lease_teardown_trigger" {
  # checkov:skip=CKV_AWS_297: "AWS-managed key is proportionate: the schedule carries no sensitive payload, same reasoning as the MemPalace trigger"
  name       = "${local.name_prefix}-netbird-lease-teardown-trigger"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(15 minutes)"

  target {
    arn      = aws_lambda_function.netbird_lease_teardown_trigger.arn
    role_arn = aws_iam_role.netbird_lease_teardown_scheduler.arn

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 300
    }
  }
}

resource "aws_iam_role" "netbird_lease_teardown_scheduler" {
  name = "${local.name_prefix}-netbird-lease-teardown-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-netbird-lease-teardown-scheduler-role"
  })
}

resource "aws_iam_role_policy" "netbird_lease_teardown_scheduler" {
  name = "netbird-lease-teardown-scheduler-invoke"
  role = aws_iam_role.netbird_lease_teardown_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeLeaseTeardownTriggerLambda"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.netbird_lease_teardown_trigger.arn
      }
    ]
  })
}
