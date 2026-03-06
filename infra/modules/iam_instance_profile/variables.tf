variable "name" {
  description = "Name of the instance profile"
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role to attach"
  type        = string
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
