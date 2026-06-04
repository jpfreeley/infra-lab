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
  description = "A valid KMS key policy JSON document. If not specified and use_standard_policy is true, the standard policy template will be used."
  type        = string
  default     = null
}

variable "use_standard_policy" {
  description = "Use the standardized key policy template instead of a custom policy. Ignored if 'policy' is provided."
  type        = bool
  default     = true
}

variable "key_administrator_arns" {
  description = "List of IAM ARNs that can administer the key (manage lifecycle, not use for encryption)."
  type        = list(string)
  default     = []
}

variable "key_user_arns" {
  description = "List of IAM ARNs that can use the key for encryption/decryption."
  type        = list(string)
  default     = []
}

variable "service_principal_arns" {
  description = "List of AWS service principals that need access to the key (e.g., cloudtrail.amazonaws.com)."
  type        = list(string)
  default     = []
}

variable "cross_account_arns" {
  description = "List of cross-account ARNs that need decrypt/describe access to the key."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A map of tags to assign to the object"
  type        = map(string)
  default     = {}
}
