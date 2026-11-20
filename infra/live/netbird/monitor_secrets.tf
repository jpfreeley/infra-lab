# Tablet Monitor Secrets (ADR-038)
#
# Terraform creates the secret SHELLS only (secret_string = null), as for the
# server's secrets in secrets.tf. Values are written out of band and never
# appear in this repo, a .tfvars file or a variable default. Assume into the
# NetBird account first (OrganizationAccountAccessRole), then:
#
#   # NetBird setup key: one use, not ephemeral, auto-group "monitors".
#   # Created in the NetBird dashboard (Setup Keys). Copy it, then:
#   pbpaste | tr -d '\n' | aws secretsmanager put-secret-value \
#     --secret-id infra-lab-netbird/tablet-monitor/setup-key --secret-string file:///dev/stdin
#
#   # ADB key pair the tablets already trust (ADR-038 section 4), as JSON
#   # {private, public}. Read from the operator's ~/.android, never printed:
#   python3 -c 'import json,os; d=os.path.expanduser("~/.android/"); print(json.dumps({"private": open(d+"adbkey").read(), "public": open(d+"adbkey.pub").read()}))' \
#     | aws secretsmanager put-secret-value \
#         --secret-id infra-lab-netbird/tablet-monitor/adb-key --secret-string file:///dev/stdin
#
#   # ntfy topic for red check-in reports: a random, unguessable name.
#   printf 'tablets-%s' "$(openssl rand -hex 16)" | aws secretsmanager put-secret-value \
#     --secret-id infra-lab-netbird/tablet-monitor/ntfy-topic --secret-string file:///dev/stdin
#
#   # Inventory: JSON {"tablets": [{name, host, package, printer, live_label,
#   # orders_pattern}]}. printer is "none", "bluetooth:<name>", "usb:<product>"
#   # or "plugin:<package>" (ADR-038 section 5). Holds site details, so it
#   # lives here and not in the repo.
#   aws secretsmanager put-secret-value \
#     --secret-id infra-lab-netbird/tablet-monitor/inventory --secret-string file://inventory.json

module "monitor_setup_key" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/tablet-monitor/setup-key"
  description   = "NetBird setup key the tablet monitor enrolls with (one use, auto-group monitors). Value set out of band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.netbird_kms.key_arn

  tags = local.common_tags
}

module "monitor_adb_key" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/tablet-monitor/adb-key"
  description   = "ADB RSA key pair the tablets already trust, JSON {private, public}. Value set out of band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.netbird_kms.key_arn

  tags = local.common_tags
}

module "monitor_ntfy_topic" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/tablet-monitor/ntfy-topic"
  description   = "ntfy topic for red tablet check-in reports. Unguessable name; value set out of band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.netbird_kms.key_arn

  tags = local.common_tags
}

module "monitor_inventory" {
  source = "../../modules/secrets_manager"

  secret_name   = "${local.name_prefix}/tablet-monitor/inventory"
  description   = "Tablet inventory for the monitor, JSON {tablets: [...]}. Holds site details; value set out of band, never via Terraform."
  secret_string = null
  kms_key_arn   = module.netbird_kms.key_arn

  tags = local.common_tags
}
