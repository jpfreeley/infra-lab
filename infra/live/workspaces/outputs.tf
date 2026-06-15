# WorkSpaces Account Outputs

output "vpc_id" {
  description = "The WorkSpaces VPC ID"
  value       = module.workspaces_vpc.vpc_id
}

output "vpc_cidr" {
  description = "The WorkSpaces VPC CIDR block"
  value       = module.workspaces_vpc.vpc_cidr_block
}

output "dcv_security_group_id" {
  description = "Security group ID for DCV instances"
  value       = module.dcv_sg.id
}

output "nat_enabled" {
  description = "Whether NAT Gateway is currently active"
  value       = var.enable_nat
}

output "api_url" {
  description = "Desktop provisioning API URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/desktops"
}

# DORMANT: Ollama outputs commented out — instance not active
# output "ollama_instance_id" {
#   description = "Ollama GPU instance ID"
#   value       = aws_instance.ollama.id
# }

# output "ollama_private_ip" {
#   description = "Ollama instance private IP (accessible from VPC)"
#   value       = aws_instance.ollama.private_ip
# }
