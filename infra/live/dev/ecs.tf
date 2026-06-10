# ECS Clusters and Services
# Epic: E06 - Compute (ECS Fargate API + Workers)
# Stories: S001 (Clusters), S003 (API), S005 (Workers)

###############################################################################
# ECS Clusters
###############################################################################

module "control_cluster" {
  source = "../../modules/ecs_cluster"

  name                = "${local.name_prefix}-control"
  container_insights  = true
  fargate_base        = 1
  fargate_weight      = 1
  fargate_spot_weight = 0 # No spot for control plane
  log_retention_days  = 30

  tags = local.common_tags
}

module "execution_cluster" {
  source = "../../modules/ecs_cluster"

  name                = "${local.name_prefix}-execution"
  container_insights  = true
  fargate_base        = 0
  fargate_weight      = 1
  fargate_spot_weight = 3 # Prefer spot for workers (cost optimization)
  log_retention_days  = 14

  tags = local.common_tags
}

###############################################################################
# API Service (Control Plane)
###############################################################################

module "api_service" {
  source = "../../modules/ecs_service"

  service_name    = "${local.name_prefix}-api"
  cluster_arn     = module.control_cluster.cluster_arn
  cluster_name    = module.control_cluster.cluster_name
  container_name  = "api"
  container_image = var.api_image
  container_port  = 8080

  cpu    = 512
  memory = 1024

  desired_count = 0 # Off by default in dev (cost optimization)

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_api.arn

  subnet_ids         = module.control_vpc.private_subnet_ids
  security_group_ids = [module.sg_ecs_control.id]

  target_group_arn  = var.enable_alb ? aws_lb_target_group.api_blue[0].arn : null
  enable_blue_green = var.enable_alb

  health_check_command = "curl -f http://localhost:8080/health || exit 1"

  environment_variables = {
    ENV          = local.environment
    SERVICE_NAME = "api"
  }

  log_retention_days = 30
  aws_region         = var.aws_region

  tags = local.common_tags
}

###############################################################################
# Worker Services (Execution Plane) - Tiered by resource needs
###############################################################################

# Nano workers: lightweight tasks (notifications, webhooks)
module "worker_nano" {
  source = "../../modules/ecs_service"

  service_name    = "${local.name_prefix}-worker-nano"
  cluster_arn     = module.execution_cluster.cluster_arn
  cluster_name    = module.execution_cluster.cluster_name
  container_name  = "worker"
  container_image = var.worker_image
  container_port  = null # Workers don't expose ports

  cpu    = 256
  memory = 512

  desired_count = 0 # Scale-from-zero in dev (cost optimization)

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_worker.arn

  subnet_ids         = module.execution_vpc.private_subnet_ids
  security_group_ids = [module.sg_ecs_execution.id]

  environment_variables = {
    ENV          = local.environment
    WORKER_TIER  = "nano"
    SERVICE_NAME = "worker-nano"
  }

  log_retention_days = 14
  aws_region         = var.aws_region

  tags = local.common_tags
}

# Medium workers: standard processing (data transforms, reports)
module "worker_medium" {
  source = "../../modules/ecs_service"

  service_name    = "${local.name_prefix}-worker-medium"
  cluster_arn     = module.execution_cluster.cluster_arn
  cluster_name    = module.execution_cluster.cluster_name
  container_name  = "worker"
  container_image = var.worker_image
  container_port  = null

  cpu    = 1024
  memory = 2048

  desired_count = 0 # Scale-from-zero in dev (cost optimization)

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_worker.arn

  subnet_ids         = module.execution_vpc.private_subnet_ids
  security_group_ids = [module.sg_ecs_execution.id]

  environment_variables = {
    ENV          = local.environment
    WORKER_TIER  = "medium"
    SERVICE_NAME = "worker-medium"
  }

  log_retention_days = 14
  aws_region         = var.aws_region

  tags = local.common_tags
}

# XLarge workers: heavy compute (ML inference, batch processing)
module "worker_xlarge" {
  source = "../../modules/ecs_service"

  service_name    = "${local.name_prefix}-worker-xlarge"
  cluster_arn     = module.execution_cluster.cluster_arn
  cluster_name    = module.execution_cluster.cluster_name
  container_name  = "worker"
  container_image = var.worker_image
  container_port  = null

  cpu    = 4096
  memory = 8192

  desired_count = 0 # Scale from zero — only runs when queue has messages

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_worker.arn

  subnet_ids         = module.execution_vpc.private_subnet_ids
  security_group_ids = [module.sg_ecs_execution.id]

  environment_variables = {
    ENV          = local.environment
    WORKER_TIER  = "xlarge"
    SERVICE_NAME = "worker-xlarge"
  }

  log_retention_days = 14
  aws_region         = var.aws_region

  tags = local.common_tags
}
