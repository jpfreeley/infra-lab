# RDS Auto-Stop Mechanism
# Prevents Aurora clusters from accumulating cost after the 7-day auto-restart.
#
# Flow: RDS Event (cluster started) → EventBridge → Lambda → Stop cluster
# Control: SSM Parameter /infra-lab/rds-auto-stop/enabled (true/false)
#
# To allow clusters to run (e.g., during development):
#   aws ssm put-parameter --name /infra-lab/rds-auto-stop/enabled \
#     --value false --overwrite --profile infra-lab
#
# To re-enable auto-stop:
#   aws ssm put-parameter --name /infra-lab/rds-auto-stop/enabled \
#     --value true --overwrite --profile infra-lab

###############################################################################
# SSM Parameter (control switch — enabled by default)
###############################################################################

resource "aws_ssm_parameter" "rds_auto_stop_enabled" {
  name  = "/infra-lab/rds-auto-stop/enabled"
  type  = "String"
  value = "true"

  description = "Controls RDS auto-stop Lambda. Set to 'false' to allow clusters to run."

  lifecycle {
    ignore_changes = [value] # Allow CLI override without Terraform drift
  }

  tags = merge(local.common_tags, {
    "Name" = "/infra-lab/rds-auto-stop/enabled"
  })
}

###############################################################################
# Lambda Function
###############################################################################

data "archive_file" "rds_auto_stop" {
  type        = "zip"
  source_file = "${path.module}/lambda/rds_auto_stop.py"
  output_path = "${path.module}/lambda/rds_auto_stop.zip"
}

resource "aws_lambda_function" "rds_auto_stop" {
  # checkov:skip=CKV_AWS_115: "Reserved concurrency not needed for event-driven Lambda"
  # checkov:skip=CKV_AWS_116: "DLQ not needed — failures are visible in CloudWatch"
  # checkov:skip=CKV_AWS_117: "VPC not needed — Lambda only calls RDS/SSM public APIs"
  # checkov:skip=CKV_AWS_173: "No sensitive env vars to encrypt"
  # checkov:skip=CKV_AWS_272: "Code signing not required for internal Lambda"
  function_name = "${local.name_prefix}-rds-auto-stop"
  description   = "Stops RDS clusters after auto-restart (cost control)"

  runtime  = "python3.12"
  handler  = "rds_auto_stop.handler"
  filename = data.archive_file.rds_auto_stop.output_path
  timeout  = 30

  source_code_hash = data.archive_file.rds_auto_stop.output_base64sha256

  role = aws_iam_role.rds_auto_stop.arn

  tracing_config {
    mode = "Active"
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-rds-auto-stop"
  })
}

###############################################################################
# IAM Role for Lambda
###############################################################################

resource "aws_iam_role" "rds_auto_stop" {
  name = "${local.name_prefix}-rds-auto-stop-role"

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
    "Name" = "${local.name_prefix}-rds-auto-stop-role"
  })
}

resource "aws_iam_role_policy" "rds_auto_stop" {
  name = "rds-auto-stop-permissions"
  role = aws_iam_role.rds_auto_stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StopRDSClusters"
        Effect = "Allow"
        Action = [
          "rds:StopDBCluster",
          "rds:DescribeDBClusters"
        ]
        Resource = "arn:aws:rds:${var.aws_region}:*:cluster:${local.name_prefix}-*"
      },
      {
        Sid    = "ReadSSMParameter"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = aws_ssm_parameter.rds_auto_stop_enabled.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-rds-auto-stop:*"
      },
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

###############################################################################
# EventBridge Rule (triggers on RDS cluster start events)
###############################################################################

resource "aws_cloudwatch_event_rule" "rds_cluster_started" {
  name        = "${local.name_prefix}-rds-cluster-started"
  description = "Triggers when an RDS cluster is started (including 7-day auto-restart)"

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Cluster Event"]
    detail = {
      EventCategories = ["notification"]
      Message         = [{ "prefix" : "DB cluster started" }]
    }
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-rds-cluster-started"
  })
}

resource "aws_cloudwatch_event_target" "rds_auto_stop" {
  rule = aws_cloudwatch_event_rule.rds_cluster_started.name
  arn  = aws_lambda_function.rds_auto_stop.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_auto_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_cluster_started.arn
}
