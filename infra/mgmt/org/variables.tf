# variables.tf

variable "security_audit_account_id" {
  description = "The AWS Account ID of the Security Audit account"
  type        = string
  default     = "881413600100"
}

variable "region" {
  description = "The AWS region where Security Hub standards will be enabled"
  type        = string
  default     = "us-east-1"
}

variable "notification_email" {
  type = string
  #sensitive   = true
  description = "Email address to receive budget and anomaly notifications"
}
