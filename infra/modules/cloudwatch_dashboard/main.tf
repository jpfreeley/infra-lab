# CloudWatch Dashboard Module
# Epic: E10 - Observability
# Story: S003 - Dashboards: queue depth, job latency, error rate, worker crashes

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.dashboard_name
  dashboard_body = var.dashboard_body_json

}
