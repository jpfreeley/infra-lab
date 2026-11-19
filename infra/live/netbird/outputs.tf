output "url" {
  description = "NetBird dashboard and management URL (clients use this as the management server)"
  value       = "https://${var.domain}"
}

output "ready_check_url" {
  description = "Returns 200 once the stack is fully up end to end (the upstream installer's readiness probe)"
  value       = "https://${var.domain}${module.netbird.ready_check_path}"
}

output "nlb_dns_name" {
  description = "NLB DNS name (the Route53 alias target)"
  value       = aws_lb.netbird.dns_name
}

output "vpc_id" {
  description = "NetBird VPC ID"
  value       = module.netbird_vpc.vpc_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.netbird_cluster.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.netbird.service_name
}

output "log_group_name" {
  description = "CloudWatch log group (all containers, by stream prefix)"
  value       = module.netbird.log_group_name
}

output "efs_file_system_id" {
  description = "EFS holding NetBird state. Never torn down."
  value       = module.netbird.efs_file_system_id
}

output "acm_certificate_arn" {
  description = "Validated ACM certificate for the domain"
  value       = aws_acm_certificate_validation.netbird.certificate_arn
}

output "secret_names" {
  description = "Secrets Manager names to populate out of band before first start (see secrets.tf)"
  value = {
    auth_secret          = module.netbird_auth_secret.secret_name
    store_encryption_key = module.netbird_store_key.secret_name
    session_cookie_key   = module.netbird_cookie_key.secret_name
    owner                = module.netbird_owner.secret_name
  }
}
