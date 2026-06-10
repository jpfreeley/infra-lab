# Dev Environment Outputs
# Epic: E05 - Networking (Dual VPC per env)

###############################################################################
# Control VPC
###############################################################################

output "control_vpc_id" {
  description = "Control VPC ID"
  value       = module.control_vpc.vpc_id
}

output "control_vpc_cidr" {
  description = "Control VPC CIDR block"
  value       = module.control_vpc.vpc_cidr_block
}

output "control_public_subnet_ids" {
  description = "Control VPC public subnet IDs"
  value       = module.control_vpc.public_subnet_ids
}

output "control_private_subnet_ids" {
  description = "Control VPC private subnet IDs"
  value       = module.control_vpc.private_subnet_ids
}

output "control_data_subnet_ids" {
  description = "Control VPC data subnet IDs"
  value       = module.control_vpc.data_subnet_ids
}

###############################################################################
# Execution VPC
###############################################################################

output "execution_vpc_id" {
  description = "Execution VPC ID"
  value       = module.execution_vpc.vpc_id
}

output "execution_vpc_cidr" {
  description = "Execution VPC CIDR block"
  value       = module.execution_vpc.vpc_cidr_block
}

output "execution_public_subnet_ids" {
  description = "Execution VPC public subnet IDs"
  value       = module.execution_vpc.public_subnet_ids
}

output "execution_private_subnet_ids" {
  description = "Execution VPC private subnet IDs"
  value       = module.execution_vpc.private_subnet_ids
}

output "execution_data_subnet_ids" {
  description = "Execution VPC data subnet IDs"
  value       = module.execution_vpc.data_subnet_ids
}

###############################################################################
# Peering
###############################################################################

output "vpc_peering_connection_id" {
  description = "VPC peering connection between Control and Execution"
  value       = module.control_vpc.peering_connection_id
}

###############################################################################
# Security Groups
###############################################################################

output "sg_alb_control_id" {
  description = "ALB security group ID (Control VPC)"
  value       = module.sg_alb_control.id
}

output "sg_ecs_control_id" {
  description = "ECS tasks security group ID (Control VPC)"
  value       = module.sg_ecs_control.id
}

output "sg_rds_control_id" {
  description = "RDS security group ID (Control VPC)"
  value       = module.sg_rds_control.id
}

output "sg_ecs_execution_id" {
  description = "ECS workers security group ID (Execution VPC)"
  value       = module.sg_ecs_execution.id
}

output "sg_rds_execution_id" {
  description = "RDS security group ID (Execution VPC)"
  value       = module.sg_rds_execution.id
}

###############################################################################
# NAT Gateway
###############################################################################

output "control_nat_public_ips" {
  description = "Control VPC NAT Gateway public IPs"
  value       = module.control_vpc.nat_gateway_public_ips
}

output "execution_nat_public_ips" {
  description = "Execution VPC NAT Gateway public IPs"
  value       = module.execution_vpc.nat_gateway_public_ips
}
