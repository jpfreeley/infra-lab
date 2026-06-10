variable "state_machine_name" {
  description = "Name of the Step Functions state machine"
  type        = string
}

variable "definition_json" {
  description = "JSON definition of the state machine (Amazon States Language)"
  type        = string
}

variable "role_policy_json" {
  description = "JSON IAM policy for the state machine execution role"
  type        = string
}

variable "express" {
  description = "Whether to use EXPRESS type (high-volume, short-duration)"
  type        = bool
  default     = false
}

variable "log_level" {
  description = "Logging level (OFF, ALL, ERROR, FATAL)"
  type        = string
  default     = "ERROR"
  validation {
    condition     = contains(["OFF", "ALL", "ERROR", "FATAL"], var.log_level)
    error_message = "Must be OFF, ALL, ERROR, or FATAL."
  }
}

variable "log_include_execution_data" {
  description = "Include execution data in logs"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "kms_key_arn" {
  description = "KMS key ARN for log encryption (null = no encryption)"
  type        = string
  default     = null
}

variable "xray_tracing_enabled" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = true
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
