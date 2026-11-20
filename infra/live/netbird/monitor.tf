# Tablet Monitor
# ADR-038: Tablet Monitor on NetBird, Four Daily Check-Ins
#
# The instance is created running. The lease workflow (ADR-038 step 6)
# starts and stops it around each check-in window and manual lease; it is
# never in the teardown target list, so its NetBird identity survives.

module "tablet_monitor" {
  source = "../../modules/tablet_monitor"

  name      = local.name_prefix
  vpc_id    = module.netbird_vpc.vpc_id
  subnet_id = module.netbird_vpc.public_subnet_ids[0]

  management_url = "https://${var.domain}"
  checkins       = var.monitor_checkins

  setup_key_secret_arn  = module.monitor_setup_key.secret_arn
  adb_key_secret_arn    = module.monitor_adb_key.secret_arn
  ntfy_topic_secret_arn = module.monitor_ntfy_topic.secret_arn
  inventory_secret_arn  = module.monitor_inventory.secret_arn
  secrets_kms_key_arn   = module.netbird_kms.key_arn

  tags = local.common_tags
}

output "tablet_monitor_instance_id" {
  description = "Tablet monitor instance ID."
  value       = module.tablet_monitor.instance_id
}
