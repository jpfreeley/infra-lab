output "dashboard_arn" {
  description = "The ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.this.dashboard_arn
}

output "dashboard_name" {
  description = "The name of the dashboard"
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}
