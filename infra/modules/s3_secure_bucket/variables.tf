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

variable "abort_multipart_days" {
  description = "Number of days after initiation to abort incomplete multipart uploads"
  type        = number
  default     = 7
}

variable "enable_access_logging" {
  description = "Enable S3 access logging"
  type        = bool
  default     = false
}

variable "logging_target_bucket" {
  description = "Target bucket for access logs"
  type        = string
  default     = ""
}

variable "enable_event_notifications" {
  description = "Enable S3 event notifications"
  type        = bool
  default     = false
}

variable "event_notifications" {
  description = "Map of event notification configurations for lambda, sns, sqs"
  type = object({
    lambda_functions = list(object({
      arn           = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    }))
    sns_topics = list(object({
      arn           = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    }))
    sqs_queues = list(object({
      arn           = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    }))
  })
  default = {
    lambda_functions = []
    sns_topics       = []
    sqs_queues       = []
  }
}

variable "enable_replication" {
  description = "Enable cross-region replication"
  type        = bool
  default     = false
}

variable "replication_role_arn" {
  description = "IAM role ARN for replication"
  type        = string
  default     = ""
}

variable "replication_destination_bucket" {
  description = "Destination bucket ARN for replication"
  type        = string
  default     = ""
}
