# Input Variables
# Epic: E06 - Compute (ECS Fargate API + Workers)

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
  description = "The environment name (dev, staging, prod)"
  type        = string
}

variable "api_image" {
  description = "Container image for the API service (repository:tag)"
  type        = string
  default     = "public.ecr.aws/docker/library/httpd:2.4"
}

variable "worker_image" {
  description = "Container image for worker services (repository:tag)"
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:latest"
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS listeners"
  type        = string
  default     = ""
}

variable "vpc_cidr_control" {
  description = "CIDR block for the control plane VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_cidr_execution" {
  description = "CIDR block for the execution plane VPC"
  type        = string
  default     = "10.1.0.0/16"
}
