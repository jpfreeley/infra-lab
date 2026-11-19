# NetBird ECS Cluster + Service
# ADR-037: Self-Hosted NetBird Server in a Dedicated Account, Torn Down When Idle

module "netbird_cluster" {
  source = "../../modules/ecs_cluster"

  name                = local.name_prefix
  container_insights  = true
  fargate_base        = 1
  fargate_weight      = 1
  fargate_spot_weight = 0 # Stateful singleton (SQLite), never Spot
  log_retention_days  = var.log_retention_days

  tags = local.common_tags
}

module "netbird" {
  source = "../../modules/netbird_server"

  name   = local.name_prefix
  domain = var.domain

  vpc_id                     = module.netbird_vpc.vpc_id
  subnet_ids                 = module.netbird_vpc.public_subnet_ids
  assign_public_ip           = true
  ingress_security_group_ids = [module.sg_nlb.id]

  cluster_arn  = module.netbird_cluster.cluster_arn
  cluster_name = module.netbird_cluster.cluster_name

  https_target_group_arn = aws_lb_target_group.https.arn
  stun_target_group_arn  = local.embedded_stun ? aws_lb_target_group.stun[0].arn : null

  tls_mode     = var.tls_mode
  acme_email   = var.acme_email
  stun_servers = var.stun_servers

  auth_secret_arn                 = module.netbird_auth_secret.secret_arn
  store_encryption_key_secret_arn = module.netbird_store_key.secret_arn
  session_cookie_key_secret_arn   = module.netbird_cookie_key.secret_arn
  owner_secret_arn                = module.netbird_owner.secret_arn
  kms_key_arn                     = module.netbird_kms.key_arn

  cpu                = var.netbird_cpu
  memory             = var.netbird_memory
  log_retention_days = var.log_retention_days

  aws_region = var.aws_region
  project    = local.project
  tags       = local.common_tags
}
