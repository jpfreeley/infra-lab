variable "role_name" {
  description = "Name of the IAM role"
  type        = string
}

variable "description" {
  description = "Description of the IAM role"
  type        = string
  default     = "Role for GitHub Actions OIDC"
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "subject_claims" {
  description = "List of allowed subject claims (e.g., repo:org/repo:ref:refs/heads/main)"
  type        = list(string)
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds"
  type        = number
  default     = 3600
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
