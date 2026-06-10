output "proxy_id" {
  description = "The ID of the RDS Proxy"
  value       = aws_db_proxy.this.id
}

output "proxy_arn" {
  description = "The ARN of the RDS Proxy"
  value       = aws_db_proxy.this.arn
}

output "proxy_endpoint" {
  description = "The endpoint of the RDS Proxy"
  value       = aws_db_proxy.this.endpoint
}

output "proxy_role_arn" {
  description = "The ARN of the proxy IAM role"
  value       = aws_iam_role.proxy.arn
}
