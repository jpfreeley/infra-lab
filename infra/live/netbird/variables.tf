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
  description = "Passed to netbird_server. Empty (default) runs embedded STUN and creates the NLB UDP listener and target group. Non-empty (e.g. [\"stun:stun.cloudflare.com:3478\"]) disables embedded STUN and creates no UDP path."
  type        = list(string)
  default     = []
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
