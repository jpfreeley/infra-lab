variable "description" {
  description = "The description of the key as viewed in AWS console"
  type        = string
  default     = "KMS key managed by Terraform"
}

variable "alias" {
  description = "The display name of the alias. Must start with 'alias/'"
  type        = string

  validation {
    condition     = can(regex("^alias/", var.alias))
    error_message = "The alias must start with 'alias/'."
  }
}

variable "deletion_window_in_days" {
  description = "The waiting period, specified in number of days"
  type        = number
  default     = 30
}

variable "enable_key_rotation" {
  description = "Specifies whether key rotation is enabled. Defaults to true for security compliance."
  type        = bool
  default     = true
}

variable "policy" {
  description = "A valid KMS key policy JSON document. If not specified, AWS will use a default policy."
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to assign to the object"
  type        = map(string)
  default     = {}
}
