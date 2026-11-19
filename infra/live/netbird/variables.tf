# NetBird Account Variables
# ADR-037: Self-Hosted NetBird Server in a Dedicated Account, Torn Down When Idle

variable "aws_region" {
  description = "The primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "The AWS CLI profile to use locally. GitHub Actions passes an empty string, which the provider treats as null and falls back to OIDC-derived credentials."
  type        = string
  default     = "infra-lab"
}

variable "netbird_account_id" {
  description = "AWS Account ID of the dedicated NetBird account (infra/mgmt/org output netbird_account_id). Created 2026-11-19."
  type        = string
  default     = "300077301490"
}

variable "environment" {
  description = "The environment name (must be an allowed value in the org Environment tag policy)"
  type        = string
  default     = "netbird"
}

variable "domain" {
  description = "Public FQDN for the NetBird server, inside the lintwiselabs.com zone."
  type        = string
  default     = "netbird.lintwiselabs.com"
}

variable "tls_mode" {
  description = "Passed to netbird_server. \"nlb\" (ADR-037 Option A, default): TLS listener with the ACM certificate. \"traefik\" (Option B): TCP passthrough, Traefik gets a Let's Encrypt certificate."
  type        = string
  default     = "nlb"
}

variable "acme_email" {
  description = "Let's Encrypt contact email, required only when tls_mode is \"traefik\". Supply it from a local, gitignored tfvars file or -var; never commit a real address."
  type        = string
  default     = null
}

variable "stun_servers" {
  description = "Passed to netbird_server. Non-empty disables embedded STUN and creates no UDP path; empty runs embedded STUN with an NLB UDP listener and target group. Defaults to Cloudflare's public STUN (ADR-037 spike, 2026-11-19): STUN through the NLB got no reply while the same probe straight to the task worked, most likely because NLB UDP preserves the client IP and the public-subnet task replies via the IGW from its own address. Fixing that in AWS would need private subnets plus a NAT Gateway (about $32 a month). Cloudflare only learns peer public IPs. Google's public STUN is listed second so one provider's outage doesn't leave peers without STUN (they would otherwise fall back to the relay over 443)."
  type        = list(string)
  default     = ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"]
}

variable "netbird_cpu" {
  description = "Fargate task CPU units for netbird_server. Starting value, right-size from CloudWatch after real use."
  type        = number
  default     = 512
}

variable "netbird_memory" {
  description = "Fargate task memory in MiB for netbird_server. Starting value, right-size from CloudWatch after real use."
  type        = number
  default     = 2048
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 30
}
