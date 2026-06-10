variable "secret_name" {
  description = "Name/path of the secret (use prefix like infra-lab-dev/service/key)"
  type        = string
}

variable "description" {
  description = "Description of the secret"
  type        = string
  default     = "Managed by Terraform"
}

variable "secret_string" {
  description = "Initial secret value (ignored after first create). Set null to manage externally."
  type        = string
  default     = null
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (null = aws/secretsmanager default)"
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Days before permanent deletion (0 = immediate, 7-30 = recoverable)"
  type        = number
  default     = 7
}

variable "policy_json" {
  description = "JSON resource policy for the secret (null = no policy)"
  type        = string
  default     = null
}

variable "rotation_lambda_arn" {
  description = "ARN of the Lambda function for secret rotation (null = no rotation)"
  type        = string
  default     = null
}

variable "rotation_days" {
  description = "Days between automatic rotations"
  type        = number
  default     = 30
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
