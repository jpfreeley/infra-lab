output "state_machine_id" {
  description = "The ID of the state machine"
  value       = aws_sfn_state_machine.this.id
}

output "state_machine_arn" {
  description = "The ARN of the state machine"
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "The name of the state machine"
  value       = aws_sfn_state_machine.this.name
}

output "role_arn" {
  description = "The ARN of the state machine execution role"
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.this.name
}
