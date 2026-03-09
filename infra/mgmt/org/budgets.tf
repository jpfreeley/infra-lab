# --- AWS Budget ---
resource "aws_budgets_budget" "org_monthly_budget" {
  name              = "org-monthly-cost-budget"
  budget_type       = "COST"
  limit_amount      = "100.0" # Adjust this to your baseline
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2024-01-01_00:00"

  # 50% Actual Spend Alert
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  # 80% Actual Spend Alert
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  # 100% Forecasted Spend Alert (Proactive)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }
}

# --- Cost Anomaly Detection ---
# 1. Create an SNS Topic for Anomaly Alerts
resource "aws_sns_topic" "anomaly_alerts" {
  name              = "cost-anomaly-alerts-topic"
  kms_master_key_id = "alias/aws/sns" # AWS-managed SNS key
}

# 2. Subscribe your email to the SNS Topic
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.anomaly_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# 3. Create the Anomaly Monitor
resource "aws_ce_anomaly_monitor" "service_monitor" {
  name              = "AWS-Service-Monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

# 4. Create the Anomaly Subscription pointing to the SNS Topic
resource "aws_ce_anomaly_subscription" "sns_subscription" {
  name      = "Daily-Anomaly-Alerts-via-SNS"
  frequency = "IMMEDIATE"
  monitor_arn_list = [
    aws_ce_anomaly_monitor.service_monitor.arn
  ]

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["10.0"] # Alert if anomaly impact is >= $10
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  # Point to the SNS Topic instead of a direct email
  subscriber {
    type    = "SNS"
    address = aws_sns_topic.anomaly_alerts.arn
  }
}
