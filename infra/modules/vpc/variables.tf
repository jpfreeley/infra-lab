variable "name" {
  description = "Name prefix for all VPC resources"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "enable_internet_gateway" {
  description = "Whether to create an Internet Gateway"
  type        = bool
  default     = true
}

variable "public_subnets" {
  description = "List of public subnet definitions"
  type = list(object({
    cidr = string
    az   = string
  }))
  default = []
}

variable "private_subnets" {
  description = "List of private subnet definitions"
  type = list(object({
    cidr = string
    az   = string
  }))
  default = []
}

variable "data_subnets" {
  description = "List of data/DB subnet definitions"
  type = list(object({
    cidr = string
    az   = string
  }))
  default = []
}

variable "nat_gateway_count" {
  description = "Number of NAT Gateways (0=none, 1=single, 3=per-AZ HA)"
  type        = number
  default     = 1
  validation {
    condition     = contains([0, 1, 2, 3], var.nat_gateway_count)
    error_message = "NAT gateway count must be 0, 1, 2, or 3."
  }
}

variable "enable_flow_logs" {
  description = "Whether to enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "flow_log_destination_type" {
  description = "Flow log destination type (cloud-watch-logs or s3)"
  type        = string
  default     = "s3"
  validation {
    condition     = contains(["cloud-watch-logs", "s3"], var.flow_log_destination_type)
    error_message = "Must be cloud-watch-logs or s3."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the flow log destination (S3 bucket or CloudWatch log group)"
  type        = string
  default     = null
}

variable "flow_log_format" {
  description = "Custom flow log format string"
  type        = string
  default     = null
}

variable "peer_vpc_id" {
  description = "VPC ID to peer with (optional)"
  type        = string
  default     = null
}

variable "peer_vpc_cidr" {
  description = "CIDR of the peer VPC for routing (required if peer_vpc_id is set)"
  type        = string
  default     = null
}

variable "project" {
  description = "Project name for tagging"
  type        = string
  default     = "infra-lab"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
