# Database Layer (Aurora Serverless v2 + RDS Proxy)
# Epic: E07 - Data Plane (Aurora + RDS Proxy + S3)
# Stories: S001 (Aurora), S002 (RDS Proxy), S003 (Parameter Groups)

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

  min_capacity   = 0.5 # Scale to zero ACUs when idle (cost optimization)
  max_capacity   = 4
  instance_count = 1 # Single instance in dev

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = local.common_tags
}

###############################################################################
# RDS Proxy (Connection pooling for ECS tasks)
###############################################################################

module "rds_proxy_control" {
  source = "../../modules/rds_proxy"

  proxy_name         = "${local.name_prefix}-control-proxy"
  cluster_identifier = module.aurora_control.cluster_id
  subnet_ids         = module.control_vpc.data_subnet_ids
  security_group_ids = [module.sg_rds_control.id]

  secret_arns = [module.aurora_control.master_user_secret_arn]

  # Pool tuning for ECS (many short-lived connections)
  max_connections_percent      = 80
  max_idle_connections_percent = 50
  connection_borrow_timeout    = 120
  idle_client_timeout          = 1800

  aws_region = var.aws_region

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

###############################################################################
# RDS Proxy (Execution Plane)
###############################################################################

module "rds_proxy_execution" {
  source = "../../modules/rds_proxy"

  proxy_name         = "${local.name_prefix}-execution-proxy"
  cluster_identifier = module.aurora_execution.cluster_id
  subnet_ids         = module.execution_vpc.data_subnet_ids
  security_group_ids = [module.sg_rds_execution.id]

  secret_arns = [module.aurora_execution.master_user_secret_arn]

  max_connections_percent      = 80
  max_idle_connections_percent = 50
  connection_borrow_timeout    = 120
  idle_client_timeout          = 1800

  aws_region = var.aws_region

  tags = local.common_tags
}
