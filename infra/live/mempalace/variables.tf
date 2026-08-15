# MemPalace Account Variables
# ADR-034: Shared MemPalace Server as a Portable App on Dedicated Infra

variable "aws_region" {
  description = "The primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "The AWS CLI profile to use locally. GitHub Actions overrides this to an empty string (-var=\"aws_profile=\"), which the provider block treats as null — falling back to OIDC-derived credentials instead of a named profile that doesn't exist in CI."
  type        = string
  default     = "infra-lab"
}

variable "mempalace_account_id" {
  description = "AWS Account ID of the dedicated MemPalace account. Defaulted now that the account is real and permanent (created 2026-08-14, id 310697203282) — the earlier no-default design was specifically to avoid a stale/fake ID sitting in version control before the account existed; that concern no longer applies."
  type        = string
  default     = "310697203282"
}

variable "environment" {
  description = "The environment name"
  type        = string
  default     = "mempalace"
}

variable "enable_https" {
  description = "Attach an HTTPS listener (requires acm_certificate_arn). Defaults true now that mempalace.lintwiselabs.com's ACM cert is issued and validated (2026-08-14) — was false while no domain existed (ADR-034)."
  type        = bool
  default     = true
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. Defaults to the real, validated mempalace.lintwiselabs.com cert."
  type        = string
  default     = "arn:aws:acm:us-east-1:310697203282:certificate/16ea7326-c0f8-47e9-bc46-279e4d4bef02"
}

variable "mempalace_cpu" {
  description = "Fargate task CPU units for the mempalace_server module (passed through). Was temporarily bumped 256->2048 on 2026-08-15 for the bulk EFS migration (CloudWatch confirmed CPU, not EFS or client concurrency, was the bottleneck), then reverted to 256 once that finished. Raised again the same day to 512, this time as the new steady-state floor, not a temporary bump: a real post-migration usage burst (several near-simultaneous mempalace_search calls in one agent session) spiked ALB TargetResponseTime to a 15s worst case at cpu=256, CPU-bound on embedding computation (confirmed via CloudWatch — CPU jumped 10%->66% in the same minute the latency spiked, EFS PercentIOLimit stayed under 1% the whole time, ruling out storage). 256 is fine at idle but not for interactive query bursts, which matters more for this service's actual use pattern than bulk-write throughput does."
  type        = number
  default     = 512
}

variable "mempalace_memory" {
  description = "Fargate task memory in MiB for the mempalace_server module (passed through). Raised alongside mempalace_cpu (see above) to 1024 as the new steady-state floor — 1024 is Fargate's minimum allowed memory at cpu=512."
  type        = number
  default     = 1024
}

variable "embedding_device" {
  description = "Value for MEMPALACE_EMBEDDING_DEVICE (e.g. \"cpu\"). Null lets mempalace auto-detect."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 30
}
