# WorkSpaces Account Outputs
# Epic: E13 - AWS WorkSpaces Account (EC2 Spot + NICE DCV)

output "vpc_id" {
  description = "The WorkSpaces VPC ID"
  value       = module.workspaces_vpc.vpc_id
}

output "vpc_cidr" {
  description = "The WorkSpaces VPC CIDR block"
  value       = module.workspaces_vpc.vpc_cidr_block
}

output "dcv_instance_id" {
  description = "EC2 instance ID of the DCV desktop (spot)"
  value       = aws_spot_instance_request.dcv_desktop.spot_instance_id
}

output "dcv_public_ip" {
  description = "Public IP of the DCV desktop (connect via https://<ip>:8443)"
  value       = aws_spot_instance_request.dcv_desktop.public_ip
}

output "dcv_connect_url" {
  description = "URL to connect to the DCV desktop"
  value       = "https://${aws_spot_instance_request.dcv_desktop.public_ip}:8443"
}

output "dcv_security_group_id" {
  description = "Security group ID for the DCV instance"
  value       = module.dcv_sg.id
}

output "data_volume_id" {
  description = "Persistent EBS data volume ID (survives spot interruptions)"
  value       = aws_ebs_volume.data.id
}

output "nat_enabled" {
  description = "Whether NAT Gateway is currently active"
  value       = var.enable_nat
}

output "spot_request_id" {
  description = "Spot instance request ID"
  value       = aws_spot_instance_request.dcv_desktop.id
}

output "api_url" {
  description = "Desktop provisioning API URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/desktops"
}

output "ollama_instance_id" {
  description = "Ollama GPU instance ID"
  value       = aws_spot_instance_request.ollama.spot_instance_id
}

output "ollama_private_ip" {
  description = "Ollama instance private IP (accessible from VPC)"
  value       = aws_spot_instance_request.ollama.private_ip
}
