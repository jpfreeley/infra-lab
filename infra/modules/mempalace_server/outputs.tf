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
  description = "CloudWatch log group name (both containers, distinguished by stream prefix)"
  value       = aws_cloudwatch_log_group.this.name
}

output "task_security_group_id" {
  description = "Security group ID attached to the ECS task (for ALB security group rules referencing it, if not already handled via alb_security_group_id)"
  value       = module.task_sg.id
}

output "efs_file_system_id" {
  description = "EFS file system ID backing both qdrant and mempalace storage"
  value       = aws_efs_file_system.this.id
}

output "efs_qdrant_access_point_id" {
  description = "EFS access point ID for qdrant's storage volume"
  value       = aws_efs_access_point.qdrant.id
}

output "efs_mempalace_access_point_id" {
  description = "EFS access point ID for mempalace's data volume"
  value       = aws_efs_access_point.mempalace.id
}

output "execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.task.arn
}
