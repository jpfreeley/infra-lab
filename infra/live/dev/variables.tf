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
  default     = "dev"
}

variable "api_image" {
  description = "Container image for the API service"
  type        = string
  default     = "public.ecr.aws/docker/library/httpd:2.4"
}

variable "worker_image" {
  description = "Container image for worker services"
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:latest"
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS listeners"
  type        = string
  default     = ""
}

variable "enable_alb" {
  description = "Whether to deploy the ALB (false = off by default for cost savings)"
  type        = bool
  default     = false
}
