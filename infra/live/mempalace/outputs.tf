output "alb_dns_name" {
  description = "ALB DNS name — the endpoint MCP clients connect to until a real domain is decided (ADR-034)"
  value       = aws_lb.mempalace.dns_name
}

output "bearer_token_secret_arn" {
  description = "Secrets Manager ARN — populate the actual token value out-of-band (see secrets.tf)"
  value       = module.mempalace_token.secret_arn
}

output "bearer_token_secret_name" {
  description = "Secrets Manager secret name, for `aws secretsmanager put-secret-value --secret-id`"
  value       = module.mempalace_token.secret_name
}

output "vpc_id" {
  description = "MemPalace VPC ID"
  value       = module.mempalace_vpc.vpc_id
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.mempalace.service_name
}

output "log_group_name" {
  description = "CloudWatch log group (both containers)"
  value       = module.mempalace.log_group_name
}

output "acm_certificate_arn" {
  description = "Validated ACM cert ARN for mempalace.lintwiselabs.com — supply as var.acm_certificate_arn once ready to set enable_https=true"
  value       = aws_acm_certificate_validation.mempalace.certificate_arn
}
