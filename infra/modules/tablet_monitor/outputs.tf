output "instance_id" {
  description = "Monitor instance ID (the lease workflow starts and stops it, ADR-038 step 6)."
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "Monitor security group (no inbound rules)."
  value       = aws_security_group.this.id
}

output "role_name" {
  description = "Monitor instance role."
  value       = aws_iam_role.this.name
}

output "code_bucket" {
  description = "Bucket that holds monitor.py (downloaded at every service start)."
  value       = module.code_bucket.bucket_id
}
