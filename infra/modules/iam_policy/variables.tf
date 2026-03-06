
variable "policy_name" {
  description = "Name of the IAM policy"
  type        = string
}

variable "description" {
  description = "Description of the IAM policy"
  type        = string
  default     = "Managed by Terraform"
}

variable "policy" {
  description = "JSON policy document"
  type        = string
}

variable "attach_to" {
  description = "Map of entities to attach the policy to. Format: { key = { users = [], roles = [], groups = [] } }"
  type = map(object({
    users  = optional(list(string))
    roles  = optional(list(string))
    groups = optional(list(string))
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to the IAM policy"
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "infra-lab"
}
