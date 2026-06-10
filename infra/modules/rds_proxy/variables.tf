variable "proxy_name" {
  description = "Name of the RDS Proxy"
  type        = string
}

variable "cluster_identifier" {
  description = "Identifier of the Aurora cluster to proxy"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the proxy (same as Aurora)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the proxy"
  type        = list(string)
}

variable "secret_arns" {
  description = "ARNs of Secrets Manager secrets for proxy auth"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt secrets"
  type        = string
  default     = null
}

variable "idle_client_timeout" {
  description = "Seconds before idle connections are closed"
  type        = number
  default     = 1800
}

variable "debug_logging" {
  description = "Enable debug logging for the proxy"
  type        = bool
  default     = false
}

variable "connection_borrow_timeout" {
  description = "Seconds to wait for a connection from the pool"
  type        = number
  default     = 120
}

variable "max_connections_percent" {
  description = "Maximum connections as percentage of DB max"
  type        = number
  default     = 80
}

variable "max_idle_connections_percent" {
  description = "Maximum idle connections as percentage"
  type        = number
  default     = 50
}

variable "session_pinning_filters" {
  description = "Session pinning filters (empty = no pinning)"
  type        = list(string)
  default     = []
}

variable "aws_region" {
  description = "AWS region for KMS condition"
  type        = string
  default     = "us-east-1"
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
