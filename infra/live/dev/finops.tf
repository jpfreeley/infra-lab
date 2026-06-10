# FinOps Controls (Cost Allocation + Budgets + Anomaly Detection)
# Epic: E11 - FinOps
# Stories: S001 (Tags), S002 (Budgets), S003 (Anomaly Detection)
#
# Note: Org-level tag policies and budgets exist from E03.
# This adds per-environment granularity for the dev workload account.

###############################################################################
# Per-Environment Budget (S002)
###############################################################################

resource "aws_budgets_budget" "dev_monthly" {
  name         = "${local.name_prefix}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Environment$${local.environment}"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["infra-lab-alerts@example.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["infra-lab-alerts@example.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["infra-lab-alerts@example.com"]
  }
}

###############################################################################
# Per-Service Budgets (S002 - granular cost visibility)
###############################################################################

resource "aws_budgets_budget" "compute" {
  name         = "${local.name_prefix}-compute-budget"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Container Service", "AWS Fargate"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["infra-lab-alerts@example.com"]
  }
}

resource "aws_budgets_budget" "database" {
  name         = "${local.name_prefix}-database-budget"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Relational Database Service"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["infra-lab-alerts@example.com"]
  }
}

###############################################################################
# Cost Anomaly Detection (S003)
###############################################################################

resource "aws_ce_anomaly_monitor" "service" {
  name              = "${local.name_prefix}-service-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "alerts" {
  name = "${local.name_prefix}-anomaly-alerts"

  monitor_arn_list = [aws_ce_anomaly_monitor.service.arn]

  frequency = "DAILY"

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["10"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  subscriber {
    type    = "EMAIL"
    address = "infra-lab-alerts@example.com"
  }
}
