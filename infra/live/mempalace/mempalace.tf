# MemPalace ECS Cluster + Service
# ADR-034: Shared MemPalace Server as a Portable App on Dedicated Infra

module "mempalace_cluster" {
  source = "../../modules/ecs_cluster"

  name                = local.name_prefix
  container_insights  = true
  fargate_base        = 1
  fargate_weight      = 1
  fargate_spot_weight = 0 # Not spot — this is a stateful singleton, not a fault-tolerant worker
  log_retention_days  = var.log_retention_days

  tags = local.common_tags
}

module "mempalace" {
  source = "../../modules/mempalace_server"

  name = local.name_prefix

  vpc_id                = module.mempalace_vpc.vpc_id
  subnet_ids            = module.mempalace_vpc.public_subnet_ids
  assign_public_ip      = true
  alb_security_group_id = module.sg_alb.id

  cluster_arn  = module.mempalace_cluster.cluster_arn
  cluster_name = module.mempalace_cluster.cluster_name

  target_group_arn        = aws_lb_target_group.mempalace.arn
  bearer_token_secret_arn = module.mempalace_token.secret_arn
  kms_key_arn             = module.mempalace_kms.key_arn

  cpu                = var.mempalace_cpu
  memory             = var.mempalace_memory
  embedding_device   = var.embedding_device
  log_retention_days = var.log_retention_days

  aws_region = var.aws_region
  project    = local.project
  tags       = local.common_tags
}

# MagNet Legal instance — second, independent mempalace_server on the same
# shared VPC/cluster/ALB. Own EFS, own task definition, own ECS service
# (the module creates all three internally per instantiation, exactly the
# reuse it was designed for — see docs/adr/034-shared-mempalace-server.md,
# "MagNet Legal Instance"). Everything below this point in the module's own
# inputs is intentionally separate from module.mempalace above: own target
# group, own bearer token secret, own sizing.
module "mempalace_magnetlegal" {
  source = "../../modules/mempalace_server"

  name = local.magnetlegal_prefix

  vpc_id                = module.mempalace_vpc.vpc_id
  subnet_ids            = module.mempalace_vpc.public_subnet_ids
  assign_public_ip      = true
  alb_security_group_id = module.sg_alb.id

  cluster_arn  = module.mempalace_cluster.cluster_arn
  cluster_name = module.mempalace_cluster.cluster_name

  target_group_arn        = aws_lb_target_group.magnetlegal.arn
  bearer_token_secret_arn = module.mempalace_magnetlegal_token.secret_arn
  kms_key_arn             = module.mempalace_kms.key_arn

  cpu                = var.magnetlegal_cpu
  memory             = var.magnetlegal_memory
  embedding_device   = var.embedding_device
  log_retention_days = var.log_retention_days

  aws_region = var.aws_region
  project    = local.project
  tags       = local.common_tags
}
