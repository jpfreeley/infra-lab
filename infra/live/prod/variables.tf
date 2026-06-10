variable "aws_region" {
  description = "The primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "The AWS CLI profile to use"
  type        = string
  default     = "infra-lab"
}

variable "environment" {
  description = "The environment name"
  type        = string
  default     = "prod"
}
