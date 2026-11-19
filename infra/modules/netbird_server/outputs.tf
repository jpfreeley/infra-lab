output "service_id" {
  description = "The ID of the ECS service"
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "The ARN of the task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  description = "CloudWatch log group name (all containers, distinguished by stream prefix)"
  value       = aws_cloudwatch_log_group.this.name
}

output "task_security_group_id" {
  description = "Security group ID attached to the ECS task"
  value       = module.task_sg.id
}

output "efs_file_system_id" {
  description = "EFS file system ID holding NetBird state (and ACME state in tls_mode \"traefik\"). Never part of a teardown target list."
  value       = aws_efs_file_system.this.id
}

output "efs_data_access_point_id" {
  description = "EFS access point ID for /var/lib/netbird"
  value       = aws_efs_access_point.data.id
}

output "execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.task.arn
}

output "https_port" {
  description = "Container port for the HTTPS target group (Traefik entrypoint)"
  value       = var.https_port
}

output "stun_port" {
  description = "Container UDP port for the STUN target group. Null when embedded STUN is disabled."
  value       = length(var.stun_servers) == 0 ? var.stun_port : null
}

output "health_check_port" {
  description = "Port for the target groups' HTTP health check"
  value       = var.health_port
}

output "health_check_path" {
  description = "Path for the target groups' HTTP health check"
  value       = "/health"
}

output "ready_check_path" {
  description = "End-to-end readiness probe through the public endpoint (the same probe the upstream installer waits on)"
  value       = "/oauth2/.well-known/openid-configuration"
}
