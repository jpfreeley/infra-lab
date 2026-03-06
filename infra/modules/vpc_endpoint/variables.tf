variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "service_name" {
  description = "The service name (e.g., com.amazonaws.us-east-1.s3)"
  type        = string
}

variable "endpoint_type" {
  description = "The type of endpoint (Interface or Gateway)"
  type        = string
  default     = "Interface"
  validation {
    condition     = contains(["Interface", "Gateway"], var.endpoint_type)
    error_message = "Endpoint type must be either Interface or Gateway."
  }
}

variable "security_group_ids" {
  description = "List of security group IDs (Interface only)"
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "List of subnet IDs (Interface only)"
  type        = list(string)
  default     = []
}

variable "private_dns_enabled" {
  description = "Whether to enable private DNS (Interface only)"
  type        = bool
  default     = true
}

variable "route_table_ids" {
  description = "List of route table IDs (Gateway only)"
  type        = list(string)
  default     = []
}

variable "policy" {
  description = "A policy to attach to the endpoint (JSON)"
  type        = string
  default     = null
}

variable "project" {
  description = "Project name for tagging"
  type        = string
  default     = "infra-lab"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
