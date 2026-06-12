# WorkSpaces Account Variables
# Epic: E13 - AWS WorkSpaces Account

variable "aws_region" {
  description = "The primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "The AWS CLI profile to use"
  type        = string
  default     = "infra-lab"
}

variable "environment" {
  description = "The environment name"
  type        = string
  default     = "sandbox"
}

variable "enable_nat" {
  description = "Enable NAT Gateway for outbound internet from private subnets (costs ~$0.045/hr when active)"
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "EC2 instance type for the DCV desktop"
  type        = string
  default     = "t3.large"
}

variable "allowed_ip_cidrs" {
  description = "List of CIDR blocks allowed to connect to the DCV desktop (your IP/VPN)"
  type        = list(string)
  default     = [] # Set via tfvars — your public IP
}

variable "api_secret" {
  description = "Shared secret for the desktop provisioning API (X-API-Key header)"
  type        = string
  sensitive   = true
  default     = "change-me-to-a-real-secret"
}
