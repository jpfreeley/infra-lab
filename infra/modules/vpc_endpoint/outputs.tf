output "id" {
  description = "The ID of the VPC endpoint"
  value       = aws_vpc_endpoint.this.id
}

output "arn" {
  description = "The ARN of the VPC endpoint"
  value       = aws_vpc_endpoint.this.arn
}

output "dns_entry" {
  description = "DNS entries for the endpoint"
  value       = aws_vpc_endpoint.this.dns_entry
}
