output "cluster_id" {
  description = "The ID of the Aurora cluster"
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "The ARN of the Aurora cluster"
  value       = aws_rds_cluster.this.arn
}

output "cluster_endpoint" {
  description = "The cluster writer endpoint"
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "The cluster reader endpoint"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_port" {
  description = "The port of the cluster"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "The name of the default database"
  value       = aws_rds_cluster.this.database_name
}

output "master_username" {
  description = "The master username"
  value       = aws_rds_cluster.this.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret for the master password"
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}
