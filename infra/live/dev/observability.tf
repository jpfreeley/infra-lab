# Observability (Dashboards + Alarms)
# Epic: E10 - Observability
# Stories: S001-S004
#
# Strategy: CloudWatch-native observability (no OTel collector sidecar in dev)
# to minimize compute costs. OTel can be added in prod as an ECS sidecar.

###############################################################################
# SNS Topic for Alarm Notifications
###############################################################################

resource "aws_sns_topic" "alarms" {
  # checkov:skip=CKV_AWS_26: "SNS encryption not required in dev for cost optimization"
  name = "${local.name_prefix}-alarms"

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-alarms"
  })
}

###############################################################################
# Operations Dashboard (S003)
###############################################################################

module "ops_dashboard" {
  source = "../../modules/cloudwatch_dashboard"

  dashboard_name = "${local.name_prefix}-operations"

  dashboard_body_json = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title = "ECS CPU Utilization"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", "${local.name_prefix}-control", "ServiceName", "${local.name_prefix}-api"],
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title = "ECS Memory Utilization"
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", "${local.name_prefix}-control", "ServiceName", "${local.name_prefix}-api"],
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "SQS Queue Depth"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${local.name_prefix}-worker-nano"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${local.name_prefix}-worker-medium"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${local.name_prefix}-worker-xlarge"],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "SQS DLQ Messages (Failures)"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${local.name_prefix}-worker-nano-dlq"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${local.name_prefix}-worker-medium-dlq"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${local.name_prefix}-worker-xlarge-dlq"],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title = "ALB Request Count + 5xx Errors"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${local.name_prefix}-api-alb"],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", "${local.name_prefix}-api-alb"],
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title = "ALB Target Response Time (p95)"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "${local.name_prefix}-api-alb"],
          ]
          period = 60
          stat   = "p95"
          region = var.aws_region
        }
      }
    ]
  })
}

###############################################################################
# Alarms (S004)
###############################################################################

module "service_alarms" {
  source = "../../modules/cloudwatch_alarms"

  alarm_actions = [aws_sns_topic.alarms.arn]

  alarms = [
    {
      name                = "${local.name_prefix}-api-cpu-high"
      description         = "API CPU > 85% for 5 minutes"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 2
      metric_name         = "CPUUtilization"
      namespace           = "AWS/ECS"
      period              = 300
      statistic           = "Average"
      threshold           = 85
      dimensions = {
        ClusterName = "${local.name_prefix}-control"
        ServiceName = "${local.name_prefix}-api"
      }
    },
    {
      name                = "${local.name_prefix}-api-5xx-high"
      description         = "ALB 5xx errors > 10 in 5 minutes"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      metric_name         = "HTTPCode_Target_5XX_Count"
      namespace           = "AWS/ApplicationELB"
      period              = 300
      statistic           = "Sum"
      threshold           = 10
      treat_missing_data  = "notBreaching"
      dimensions = {
        LoadBalancer = "${local.name_prefix}-api-alb"
      }
    },
    {
      name                = "${local.name_prefix}-dlq-messages"
      description         = "DLQ has messages (processing failures)"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      metric_name         = "ApproximateNumberOfMessagesVisible"
      namespace           = "AWS/SQS"
      period              = 300
      statistic           = "Sum"
      threshold           = 0
      dimensions = {
        QueueName = "${local.name_prefix}-worker-medium-dlq"
      }
    },
    {
      name                = "${local.name_prefix}-queue-depth-high"
      description         = "Queue backlog > 100 messages for 10 minutes"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 2
      metric_name         = "ApproximateNumberOfMessagesVisible"
      namespace           = "AWS/SQS"
      period              = 300
      statistic           = "Sum"
      threshold           = 100
      dimensions = {
        QueueName = "${local.name_prefix}-worker-medium"
      }
    },
  ]

  tags = local.common_tags
}
