variable "name" {
  description = "The name of the S3 bucket. Must be globally unique."
  type        = string

  validation {
    condition     = length(var.name) > 3 && length(var.name) <= 63
    error_message = "Bucket name must be between 3 and 63 characters."
  }
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key for SSE-KMS encryption"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "KMS key ARN must start with 'arn:aws:kms:'."
  }
}

variable "lifecycle_days" {
  description = "Number of days to retain non-current versions before expiration"
  type        = number
  default     = 90
}
