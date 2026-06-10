variable "service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster (for log group naming)"
  type        = string
}

variable "container_name" {
  description = "Name of the container"
  type        = string
}

variable "container_image" {
  description = "Container image (repository:tag)"
  type        = string
}

variable "container_port" {
  description = "Container port to expose (null for workers)"
  type        = number
  default     = null
}

variable "cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "CPU must be 256, 512, 1024, 2048, or 4096."
  }
}

variable "memory" {
  description = "Memory in MiB for the task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

variable "launch_type" {
  description = "Launch type (FARGATE or FARGATE_SPOT for workers)"
  type        = string
  default     = "FARGATE"
  validation {
    condition     = contains(["FARGATE", ""], var.launch_type)
    error_message = "Launch type must be FARGATE or empty (for capacity provider)."
  }
}

variable "execution_role_arn" {
  description = "ARN of the task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the task role"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the service"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the service"
  type        = list(string)
}

variable "target_group_arn" {
  description = "ALB target group ARN (null for workers)"
  type        = string
  default     = null
}

variable "enable_blue_green" {
  description = "Enable Blue/Green deployment via CodeDeploy"
  type        = bool
  default     = false
}

variable "environment_variables" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets from SSM/Secrets Manager (name = ARN)"
  type        = map(string)
  default     = {}
}

variable "health_check_command" {
  description = "Health check command (null to disable)"
  type        = string
  default     = null
}

variable "health_check_grace_period" {
  description = "Health check start period in seconds"
  type        = number
  default     = 60
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for CloudWatch log encryption (null to disable)"
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region for CloudWatch logs"
  type        = string
  default     = "us-east-1"
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
