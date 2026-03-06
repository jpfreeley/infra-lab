variable "aws_region" {
  description = "The primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "The AWS CLI profile to use for the default provider"
  type        = string
  default     = "infra-lab"
}

variable "environment" {
  description = "The environment name (dev, staging, prod)"
  type        = string
}

variable "target_role_arn" {
  description = "The ARN of the IAM role to assume in the target account"
  type        = string
}

variable "target_external_id" {
  description = "Optional external ID for the AssumeRole operation"
  type        = string
  default     = null
}
