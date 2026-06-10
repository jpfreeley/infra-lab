# CloudWatch Alarms Module
# Epic: E10 - Observability
# Story: S004 - Alarms: burn-rate + CodeDeploy rollback triggers

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = { for alarm in var.alarms : alarm.name => alarm }

  alarm_name          = each.value.name
  alarm_description   = each.value.description
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  treat_missing_data  = each.value.treat_missing_data

  dimensions = each.value.dimensions

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(var.tags, {
    "Name"      = each.value.name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}
