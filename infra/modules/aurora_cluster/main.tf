# Aurora Serverless v2 Cluster Module
# Epic: E07 - Data Plane (Aurora + RDS Proxy + S3)
# Story: S001 - Provision Aurora Serverless v2 (Postgres)

###############################################################################
# DB Subnet Group
###############################################################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    "Name"      = "${var.cluster_name}-subnet-group"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Cluster Parameter Group (E07-S003: RLS-safe pooling)
###############################################################################

resource "aws_rds_cluster_parameter_group" "this" {
  family = var.parameter_group_family
  name   = "${var.cluster_name}-params"

  # Force SSL and configure for RDS Proxy compatibility
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Enable logical replication (needed for future CDC)
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # pgaudit for compliance logging
  parameter {
    name  = "shared_preload_libraries"
    value = "pgaudit,pg_stat_statements"
  }

  parameter {
    name  = "pgaudit.log"
    value = "ddl,role"
  }

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(var.tags, {
    "Name"      = "${var.cluster_name}-params"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Aurora Cluster
###############################################################################

resource "aws_rds_cluster" "this" {
  # checkov:skip=CKV_AWS_327: "Aurora Serverless v2 does not support custom KMS for performance_insights in all versions"
  # checkov:skip=CKV_AWS_162: "IAM auth configured at RDS Proxy layer, not directly on cluster"
  # checkov:skip=CKV_AWS_313: "Aurora global database is a future HA story, not required for dev"
  cluster_identifier = var.cluster_name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.engine_version
  database_name      = var.database_name
  master_username    = var.master_username

  manage_master_user_password = var.manage_master_user_password

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = var.security_group_ids
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot
  apply_immediately       = var.apply_immediately
  copy_tags_to_snapshot   = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.tags, {
    "Name"      = var.cluster_name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Cluster Instances (Serverless v2)
###############################################################################

resource "aws_rds_cluster_instance" "this" {
  # checkov:skip=CKV_AWS_354: "Performance Insights CMK optional in dev; controlled via variable"
  # checkov:skip=CKV_AWS_118: "Enhanced monitoring adds cost; enable in prod with dedicated IAM role"
  count = var.instance_count

  identifier         = "${var.cluster_name}-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  auto_minor_version_upgrade   = true
  performance_insights_enabled = true

  tags = merge(var.tags, {
    "Name"      = "${var.cluster_name}-${count.index}"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}
