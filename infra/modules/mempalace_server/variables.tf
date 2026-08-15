###############################################################################
# Identity / naming
###############################################################################

variable "name" {
  description = "Name prefix for all resources created by this module (e.g. \"mempalace\")."
  type        = string
}

###############################################################################
# Networking (bring-your-own VPC — no VPC/subnet creation in this module,
# so it can be dropped into any environment's existing network)
###############################################################################

variable "vpc_id" {
  description = "VPC ID to deploy into."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the ECS task and EFS mount targets. Public subnets with assign_public_ip=true (default) avoid a NAT Gateway; pass private subnets and set assign_public_ip=false if the consuming environment already has NAT/egress."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign a public IP to the task. Default true (no-NAT-Gateway topology, per ADR-034/ADR-031 cost precedent). Set false if subnets already route egress via NAT."
  type        = bool
  default     = true
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB (or other trusted front door) allowed to reach the mempalace container port. The task's own security group only accepts ingress from this SG — never direct public ingress to the task."
  type        = string
}

###############################################################################
# ECS cluster (bring-your-own — created outside this module)
###############################################################################

variable "cluster_arn" {
  description = "ARN of the ECS cluster to run the service in."
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster (used only for CloudWatch log group naming)."
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN for the mempalace container. Null skips ALB attachment (e.g. testing without a front door)."
  type        = string
  default     = null
}

###############################################################################
# Auth — bearer token
###############################################################################

variable "bearer_token_secret_arn" {
  description = "ARN of an existing Secrets Manager secret holding MEMPALACE_MCP_HTTP_TOKEN. This module never generates, reads, or writes the token value itself — populate the secret out-of-band (e.g. `aws secretsmanager put-secret-value`) before or after apply. Never pass the token as a plain variable."
  type        = string
}

###############################################################################
# Encryption
###############################################################################

variable "kms_key_arn" {
  description = "KMS key ARN for EFS and CloudWatch Logs encryption. Null falls back to the AWS-managed default key (not recommended for anything beyond throwaway testing)."
  type        = string
  default     = null
}

###############################################################################
# Compute sizing — deliberately conservative defaults; right-size from real
# CloudWatch metrics after the first deploy rather than guessing (see ADR-034)
###############################################################################

variable "cpu" {
  description = "Fargate task CPU units, shared across both containers (256, 512, 1024, 2048, 4096)."
  type        = number
  default     = 256
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "CPU must be 256, 512, 1024, 2048, or 4096."
  }
}

variable "memory" {
  description = "Fargate task memory in MiB, shared across both containers."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of tasks. This app is a singleton (one Qdrant + one mempalace share one EFS-backed dataset) — do not scale beyond 1 without a different storage design."
  type        = number
  default     = 1
  validation {
    condition     = var.desired_count <= 1
    error_message = "mempalace_server is a singleton service (shared EFS-backed Qdrant data); desired_count must be 0 or 1."
  }
}

###############################################################################
# Images
###############################################################################

variable "qdrant_image" {
  description = "Qdrant container image."
  type        = string
  default     = "qdrant/qdrant:latest"
}

variable "mempalace_image" {
  description = "MemPalace server container image."
  type        = string
  default     = "ghcr.io/mempalace/mempalace:latest"
}

variable "mempalace_port" {
  description = "Port mempalace serve binds to (also the ALB target group port)."
  type        = number
  default     = 8765
}

variable "qdrant_port" {
  description = "Qdrant REST API port, reached by the mempalace container over localhost only — never exposed outside the task."
  type        = number
  default     = 6333
}

variable "embedding_device" {
  description = "Value for MEMPALACE_EMBEDDING_DEVICE (e.g. \"cpu\"). Null omits the env var and lets mempalace auto-detect."
  type        = string
  default     = null
}

###############################################################################
# Observability
###############################################################################

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 30
}

variable "aws_region" {
  description = "AWS region (used for CloudWatch log configuration)."
  type        = string
  default     = "us-east-1"
}

variable "health_check_grace_period" {
  description = "ALB target group / task health check grace period in seconds (embedding model load on first start can take longer than a typical web service)."
  type        = number
  default     = 90
}

###############################################################################
# Tagging
###############################################################################

variable "project" {
  description = "Project name for tagging."
  type        = string
  default     = "infra-lab"
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
