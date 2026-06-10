variable "name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "fargate_base" {
  description = "Base count for FARGATE capacity provider"
  type        = number
  default     = 1
}

variable "fargate_weight" {
  description = "Weight for FARGATE capacity provider"
  type        = number
  default     = 1
}

variable "fargate_spot_weight" {
  description = "Weight for FARGATE_SPOT capacity provider (0 = disabled)"
  type        = number
  default     = 0
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for CloudWatch log encryption (null to disable)"
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
