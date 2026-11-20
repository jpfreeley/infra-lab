variable "name" {
  description = "Name prefix for every resource (for example infra-lab-netbird)."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the NetBird account (public-only, no NAT)."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet for the instance. It needs a public IPv4 address for outbound access, because the VPC has no NAT gateway."
  type        = string
}

variable "instance_type" {
  description = "Instance type. x86_64 only: Google publishes the Linux adb (platform-tools) for x86_64 only."
  type        = string
  default     = "t3.nano"
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 8
}

variable "management_url" {
  description = "NetBird management URL the monitor enrolls with (for example https://netbird.example.com)."
  type        = string
}

variable "netbird_hostname" {
  description = "Hostname the monitor registers as in NetBird. The status page is at http://<hostname>.<netbird dns domain>:8080/."
  type        = string
  default     = "tablet-monitor"
}

variable "checkins" {
  description = "Check-in times and IANA zone, same value as the NETBIRD_CHECKINS repo variable (ADR-038), for example \"06:00,12:00,18:00,00:00 America/New_York\"."
  type        = string
}

variable "setup_key_secret_arn" {
  description = "Secrets Manager ARN of the NetBird setup key (one use, auto-group monitors)."
  type        = string
}

variable "adb_key_secret_arn" {
  description = "Secrets Manager ARN of the ADB key pair, JSON {private, public}."
  type        = string
}

variable "ntfy_topic_secret_arn" {
  description = "Secrets Manager ARN of the ntfy topic for red check-in reports."
  type        = string
}

variable "inventory_secret_arn" {
  description = "Secrets Manager ARN of the tablet inventory JSON."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key that encrypts the four secrets above and the code bucket."
  type        = string
}

# Pinned downloads, verified by SHA-256 at boot. To upgrade, change the
# version and the checksum together (NetBird publishes a checksums file per
# release; Google publishes a SHA-1 in repository2-3.xml, so compute the
# SHA-256 from a download whose SHA-1 matches).
variable "netbird_version" {
  description = "NetBird client release (keep in step with the server)."
  type        = string
  default     = "0.83.1"
}

variable "netbird_sha256" {
  description = "SHA-256 of netbird_<version>_linux_amd64.tar.gz."
  type        = string
  default     = "a7c79ea3cb61029c5565277152e1c32cd3ccb5258dc35c86d8d3a5b5793b91da"
}

variable "platform_tools_version" {
  description = "Android platform-tools release (adb)."
  type        = string
  default     = "37.0.3"
}

variable "platform_tools_sha256" {
  description = "SHA-256 of platform-tools_r<version>-linux.zip."
  type        = string
  default     = "214548146cadb2ca3508143d8a1d4be4c59de5bb837253e3ede89ed74cf450d1"
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
