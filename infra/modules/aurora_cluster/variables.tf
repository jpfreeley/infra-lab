variable "cluster_name" {
  description = "Name of the Aurora cluster"
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master username for the cluster"
  type        = string
  default     = "dbadmin"
}

variable "manage_master_user_password" {
  description = "Let RDS manage the master password in Secrets Manager"
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group (data tier)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the cluster"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for storage encryption"
  type        = string
  default     = null
}

variable "min_capacity" {
  description = "Minimum ACU capacity for Serverless v2"
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Maximum ACU capacity for Serverless v2"
  type        = number
  default     = 4
}

variable "instance_count" {
  description = "Number of cluster instances (1 for dev, 2+ for HA)"
  type        = number
  default     = 1
}

variable "backup_retention_period" {
  description = "Days to retain automated backups"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately (vs next maintenance window)"
  type        = bool
  default     = true
}

variable "parameter_group_family" {
  description = "DB parameter group family"
  type        = string
  default     = "aurora-postgresql15"
}

variable "db_parameters" {
  description = "Map of DB cluster parameter overrides"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
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
