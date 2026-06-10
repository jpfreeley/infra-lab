# Database Layer (Aurora Serverless v2)
# Epic: E07 - Data Plane (Aurora + RDS Proxy + S3)
# Stories: S001 (Aurora), S003 (Parameter Groups)
#
# Cost Strategy: Clusters should be STOPPED when not actively developing.
# RDS Proxy is omitted in dev (only needed when ECS tasks are running at scale).
# See docs/runbooks/ecs-cost-controls.md for start/stop procedures.

###############################################################################
# Aurora Cluster (Control Plane DB)
###############################################################################

module "aurora_control" {
  source = "../../modules/aurora_cluster"

  cluster_name = "${local.name_prefix}-control-db"
  subnet_ids   = module.control_vpc.data_subnet_ids

  security_group_ids = [module.sg_rds_control.id]

  engine_version = "15.4"
  database_name  = "control"

  min_capacity   = 0.5 # Minimum for Serverless v2
  max_capacity   = 4
  instance_count = 1 # Single instance in dev

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = local.common_tags
}

###############################################################################
# Aurora Cluster (Execution Plane DB - tenant workloads)
###############################################################################

module "aurora_execution" {
  source = "../../modules/aurora_cluster"

  cluster_name = "${local.name_prefix}-execution-db"
  subnet_ids   = module.execution_vpc.data_subnet_ids

  security_group_ids = [module.sg_rds_execution.id]

  engine_version = "15.4"
  database_name  = "execution"

  min_capacity   = 0.5
  max_capacity   = 8 # Higher ceiling for worker batch jobs
  instance_count = 1

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = local.common_tags
}
