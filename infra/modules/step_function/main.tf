# Step Functions State Machine Module
# Epic: E08 - Orchestration (SQS + Step Functions)
# Story: S002 - Define Step Functions state machine for job lifecycle

###############################################################################
# CloudWatch Log Group for Step Functions
###############################################################################

resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_158: "KMS encryption optional in dev; controlled via variable"
  # checkov:skip=CKV_AWS_338: "Retention varies by environment; 365d enforced in prod"
  name              = "/aws/states/${var.state_machine_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    "Name"      = "/aws/states/${var.state_machine_name}"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# IAM Role for Step Functions
###############################################################################

resource "aws_iam_role" "this" {
  name = "${var.state_machine_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    "Name"      = "${var.state_machine_name}-role"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_iam_role_policy" "this" {
  name = "state-machine-permissions"
  role = aws_iam_role.this.id

  policy = var.role_policy_json
}

# CloudWatch Logs permissions for execution logging
resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

###############################################################################
# State Machine
###############################################################################

resource "aws_sfn_state_machine" "this" {
  # checkov:skip=CKV_AWS_285: "Full execution logging (ALL) enabled in prod; ERROR-level sufficient for dev"
  name     = var.state_machine_name
  role_arn = aws_iam_role.this.arn

  definition = var.definition_json

  type = var.express ? "EXPRESS" : "STANDARD"

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this.arn}:*"
    include_execution_data = var.log_include_execution_data
    level                  = var.log_level
  }

  tracing_configuration {
    enabled = var.xray_tracing_enabled
  }

  tags = merge(var.tags, {
    "Name"      = var.state_machine_name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}
