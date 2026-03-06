
variable "role_name" {
  description = "Name of the IAM role"
  type        = string
}

variable "assume_role_policy" {
  description = "The policy that grants an entity permission to assume the role"
  type        = string
}

variable "description" {
  description = "Description of the IAM role"
  type        = string
  default     = "Managed by Terraform"
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds"
  type        = number
  default     = 3600
}

variable "attach_policy_arns" {
  description = "Map of policy ARNs to attach to the role"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to the IAM role"
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "infra-lab"
}
