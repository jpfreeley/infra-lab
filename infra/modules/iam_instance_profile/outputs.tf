output "id" {
  description = "The ID of the instance profile"
  value       = aws_iam_instance_profile.this.id
}

output "arn" {
  description = "The ARN of the instance profile"
  value       = aws_iam_instance_profile.this.arn
}
