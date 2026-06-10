# Prod Environment Outputs

output "control_vpc_id" {
  description = "Control VPC ID"
  value       = module.control_vpc.vpc_id
}

output "control_vpc_cidr" {
  description = "Control VPC CIDR block"
  value       = module.control_vpc.vpc_cidr_block
}

output "control_private_subnet_ids" {
  description = "Control VPC private subnet IDs"
  value       = module.control_vpc.private_subnet_ids
}

output "execution_vpc_id" {
  description = "Execution VPC ID"
  value       = module.execution_vpc.vpc_id
}

output "execution_vpc_cidr" {
  description = "Execution VPC CIDR block"
  value       = module.execution_vpc.vpc_cidr_block
}

output "execution_private_subnet_ids" {
  description = "Execution VPC private subnet IDs"
  value       = module.execution_vpc.private_subnet_ids
}

output "vpc_peering_connection_id" {
  description = "VPC peering connection between Control and Execution"
  value       = module.control_vpc.peering_connection_id
}

output "control_nat_public_ips" {
  description = "Control VPC NAT Gateway public IPs (per-AZ)"
  value       = module.control_vpc.nat_gateway_public_ips
}

output "execution_nat_public_ips" {
  description = "Execution VPC NAT Gateway public IPs (per-AZ)"
  value       = module.execution_vpc.nat_gateway_public_ips
}
