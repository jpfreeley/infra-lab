###############################################################################
# Identity / naming
###############################################################################

variable "name" {
  description = "Name prefix for all resources created by this module (e.g. \"netbird\")."
  type        = string
}

variable "domain" {
  description = "Public FQDN the NetBird server is reached at (e.g. \"netbird.example.com\"). Used for the OIDC issuer, dashboard redirect URIs, Traefik host rules and the server's exposedAddress. No scheme, no port."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain))
    error_message = "domain must be a bare lowercase FQDN with no scheme, port or path."
  }
}

###############################################################################
# Networking (bring-your-own VPC)
###############################################################################

variable "vpc_id" {
  description = "VPC ID to deploy into."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the ECS task and EFS mount targets. Public subnets with assign_public_ip=true (default) avoid a NAT Gateway (ADR-037, same cost pattern as ADR-034/ADR-031)."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign a public IP to the task. Default true (no-NAT topology). Set false if the subnets already route egress via NAT."
  type        = bool
  default     = true
}

variable "ingress_security_group_ids" {
  description = "Security group IDs (normally the NLB's) allowed to reach the Traefik HTTPS port and the server health check port. The task never accepts TCP from the internet directly."
  type        = list(string)
}

variable "stun_ingress_cidr_blocks" {
  description = "CIDRs allowed to reach the embedded STUN listener over UDP. STUN is a public service by nature and NLB UDP target groups always preserve the client source IP, so this is normally 0.0.0.0/0. Ignored when stun_servers is non-empty (embedded STUN is then disabled)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

###############################################################################
# ECS cluster and load balancer attachment (bring-your-own)
###############################################################################

variable "cluster_arn" {
  description = "ARN of the ECS cluster to run the service in."
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster (used only for CloudWatch log group naming)."
  type        = string
}

variable "https_target_group_arn" {
  description = "NLB target group ARN (target type ip) for Traefik's HTTPS entrypoint. In tls_mode \"nlb\" the NLB listener is TLS and this target group is TCP; in tls_mode \"traefik\" both are TCP (passthrough). Null skips attachment."
  type        = string
  default     = null
}

variable "stun_target_group_arn" {
  description = "NLB UDP target group ARN (target type ip) for embedded STUN. Null skips attachment. Must be null when stun_servers is non-empty."
  type        = string
  default     = null
}

###############################################################################
# TLS
###############################################################################

variable "tls_mode" {
  description = "Where TLS terminates. \"nlb\": NLB TLS listener with an ACM certificate (ALPN HTTP2Preferred) forwards cleartext to Traefik, which accepts h2c and HTTP/1.1 (ADR-037 Option A). \"traefik\": NLB TCP passthrough, Traefik terminates TLS with a Let's Encrypt certificate (TLS-ALPN-01) stored on EFS (ADR-037 Option B, the upstream default)."
  type        = string
  default     = "nlb"

  validation {
    condition     = contains(["nlb", "traefik"], var.tls_mode)
    error_message = "tls_mode must be \"nlb\" or \"traefik\"."
  }
}

variable "acme_email" {
  description = "Contact email for Let's Encrypt registration. Required when tls_mode is \"traefik\", ignored otherwise. Pass it from the live layer's variables; never hardcode a personal address in the module."
  type        = string
  default     = null
}

variable "proxy_protocol_trusted_cidrs" {
  description = "When non-empty, Traefik's entrypoint accepts PROXY protocol v2 from these CIDRs (normally the VPC CIDR) so NetBird sees real client IPs. Enable proxy_protocol_v2 on the HTTPS target group at the same time; a mismatch breaks every connection."
  type        = list(string)
  default     = []
}

###############################################################################
# STUN
###############################################################################

variable "stun_servers" {
  description = "External STUN URIs (e.g. [\"stun:stun.cloudflare.com:3478\"]). Empty (default) runs the embedded STUN listener on stun_port, which needs a UDP listener on the NLB. Non-empty disables embedded STUN entirely (upstream: setting stuns \"disables local STUN server\"), so no UDP path is needed at all."
  type        = list(string)
  default     = []
}

###############################################################################
# Secrets (ARNs only, values are written out of band, see README)
###############################################################################

variable "auth_secret_arn" {
  description = "Secrets Manager ARN holding the relay auth secret (injected as NB_AUTH_SECRET). Generate with `openssl rand -base64 32 | tr -d =`."
  type        = string
}

variable "store_encryption_key_secret_arn" {
  description = "Secrets Manager ARN holding the datastore encryption key (injected as NB_STORE_ENCRYPTION_KEY). Generate with `openssl rand -base64 32` and keep the padding. Losing this value makes the existing database unreadable."
  type        = string
}

variable "session_cookie_key_secret_arn" {
  description = "Secrets Manager ARN holding the embedded IdP session cookie key (injected as NB_IDP_SESSION_COOKIE_ENCRYPTION_KEY). Generate with `openssl rand -base64 32`."
  type        = string
}

variable "owner_secret_arn" {
  description = "Optional Secrets Manager ARN of a JSON secret {\"email\": ..., \"password\": ...} used to create the initial owner account at first start (upstream auth.owner), which closes the window where anyone reaching /setup first could claim the instance. Use a hex password (`openssl rand -hex 24`) so it needs no YAML escaping. Null leaves first-user creation to the /setup page."
  type        = string
  default     = null
}

###############################################################################
# Encryption
###############################################################################

variable "kms_key_arn" {
  description = "KMS key ARN for EFS, CloudWatch Logs, and the secrets' decryption grant. Null falls back to AWS-managed default keys (not recommended beyond throwaway testing)."
  type        = string
  default     = null
}

###############################################################################
# Compute sizing
###############################################################################

variable "cpu" {
  description = "Fargate task CPU units, shared across all containers (256, 512, 1024, 2048, 4096)."
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "CPU must be 256, 512, 1024, 2048, or 4096."
  }
}

variable "memory" {
  description = "Fargate task memory in MiB, shared across all containers. Upstream asks for a 2 GB VM including the OS and Docker; right-size from CloudWatch after the first real use."
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Desired number of tasks. NetBird on SQLite is a singleton (no concurrent writers), so this must be 0 or 1."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count <= 1
    error_message = "netbird_server is a singleton service (SQLite on EFS); desired_count must be 0 or 1."
  }
}

###############################################################################
# Images, pinned by digest (ADR-037; same lesson as the ADR-034 2026-09-18
# image-drift incident). Upgrade by bumping these deliberately in a PR.
# Resolve a digest without a Docker daemon via the registry API, e.g.
# HEAD https://registry-1.docker.io/v2/<repo>/manifests/<tag> with an
# anonymous pull token, reading Docker-Content-Digest.
###############################################################################

variable "netbird_server_image" {
  description = "NetBird combined server image (management, signal, relay, STUN), pinned by digest."
  type        = string
  default     = "netbirdio/netbird-server@sha256:f6acc1a6dcb48d10b867ec7e6916c62ef5c8dc2bb198aec9cc637b2dd26c06c9" # 0.83.1
}

variable "dashboard_image" {
  description = "NetBird dashboard image, pinned by digest."
  type        = string
  default     = "netbirdio/dashboard@sha256:3e8a714e2966f96201b817657cf5b6e4304b947b88341fe99639214fb440ea9c" # v2.98.0
}

variable "traefik_image" {
  description = "Traefik image, pinned by digest. Also used as the init container (it ships /bin/sh). Upstream requires v3.7.13 or newer for aliasHeadersStrategy."
  type        = string
  default     = "traefik@sha256:a6c0194dda77bcb804824580f36fa7edc56e315b1acfe933366c8b52844a78a4" # v3.7.19
}

###############################################################################
# Ports inside the task (all containers share one network namespace)
###############################################################################

variable "https_port" {
  description = "Traefik entrypoint port, the HTTPS target group's port. Kept off 443 because the dashboard image also exposes 443."
  type        = number
  default     = 8443
}

variable "server_port" {
  description = "NetBird server listen port (HTTP/1.1, WebSocket and h2c). Kept off 80 because the dashboard binds 80."
  type        = number
  default     = 8081
}

variable "stun_port" {
  description = "Embedded STUN UDP port."
  type        = number
  default     = 3478
}

variable "health_port" {
  description = "NetBird server health check port (/health). Intended as the NLB target groups' HTTP health check."
  type        = number
  default     = 9000
}

variable "metrics_port" {
  description = "NetBird server Prometheus metrics port. Not exposed outside the task."
  type        = number
  default     = 9090
}

###############################################################################
# Behavior
###############################################################################

variable "log_level" {
  description = "NetBird server log level (panic, fatal, error, warn, info, debug, trace)."
  type        = string
  default     = "info"
}

variable "disable_anonymous_metrics" {
  description = "Turn off NetBird's anonymous usage metrics reporting."
  type        = bool
  default     = true
}

###############################################################################
# Observability
###############################################################################

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 30
}

variable "aws_region" {
  description = "AWS region (used for CloudWatch log configuration)."
  type        = string
  default     = "us-east-1"
}

###############################################################################
# Tagging
###############################################################################

variable "project" {
  description = "Project name for tagging."
  type        = string
  default     = "infra-lab"
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
