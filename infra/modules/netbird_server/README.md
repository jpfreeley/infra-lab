# NetBird Server Module

Runs a self-hosted [NetBird](https://github.com/netbirdio/netbird) control
plane (management, signal, relay, STUN, dashboard, embedded Dex IdP) as a
single ECS Fargate task with EFS-backed state. See
[ADR-037](../../../docs/adr/037-netbird-server-dedicated-account.md) for the
design rationale.

Portable in the same way as `mempalace_server`: every input is a variable,
and nothing is hardcoded to infra-lab's account IDs, domain, or org layout.

## Topology

One task, four containers sharing the task's network namespace. This is the
upstream installer's single-host layout (Traefik in front of the combined
server and the dashboard), with the Docker provider replaced by Traefik's
file provider.

| Container | Role | Ports (task-local) |
| --- | --- | --- |
| `config-init` | Renders `config.yaml` and Traefik's dynamic config onto a task-local volume, then exits | none |
| `netbird-server` | Management, signal, relay (WebSocket), embedded STUN | 8081/tcp, 9000/tcp health, 3478/udp |
| `dashboard` | Web UI | 80/tcp |
| `traefik` | Only TCP entrypoint. gRPC routed as h2c, everything else HTTP/1.1 | 8443/tcp |

The caller puts an NLB in front:

- **TCP 443** to `traefik:8443` (`https_target_group_arn`).
- **UDP 3478** to `netbird-server:3478` (`stun_target_group_arn`), only
  when the embedded STUN listener is in use.

## Scope boundary

| Owned by this module | Owned by the caller |
| --- | --- |
| ECS task definition and service | VPC and subnets |
| EFS filesystem and access points | NLB, listeners, target groups |
| Task and EFS security groups | ACM certificate (tls_mode `nlb`) |
| IAM execution and task roles | Route53 records |
| CloudWatch log group | KMS key, ECS cluster |
| | Secrets Manager secrets **and their values** |

## TLS modes

| `tls_mode` | NLB HTTPS listener | Target group | Certificate |
| --- | --- | --- | --- |
| `nlb` (default) | TLS, ACM cert, ALPN `HTTP2Preferred` | TCP | ACM |
| `traefik` | TCP (passthrough) | TCP | Let's Encrypt via TLS-ALPN-01, stored on EFS |

`nlb` mode relies on Traefik accepting cleartext HTTP/2 with prior knowledge
on a plain entrypoint after the NLB terminates TLS. ADR-037 lists this as
unverified until the first live spike. `traefik` mode is the upstream
default and the fallback.

## STUN

- `stun_servers = []` (default): embedded STUN on UDP 3478. Needs a UDP
  listener and target group on the NLB.
- `stun_servers = ["stun:stun.cloudflare.com:3478"]`: upstream disables
  the embedded listener when external STUN servers are set. No UDP path is
  needed at all, and the NLB carries TCP 443 only. The STUN operator sees
  peer public IPs and nothing else.

## Health and readiness

- Target group health check: HTTP `GET /health` on port 9000
  (`health_check_port`, `health_check_path` outputs). The task security
  group allows it from `ingress_security_group_ids`.
- End-to-end readiness through the public name:
  `https://<domain>/oauth2/.well-known/openid-configuration` returns 200.
  This is the probe the upstream installer waits on.

## Secrets

The module takes ARNs only and never reads, writes, or generates values.
Write each value out of band. `openssl` ends its output with a newline and
`file:///dev/stdin` stores it verbatim, so every command strips it:

```bash
# Relay auth secret (padding stripped, as upstream does)
openssl rand -base64 32 | tr -d '=\n' | aws secretsmanager put-secret-value \
  --secret-id <auth-secret> --secret-string file:///dev/stdin

# Datastore encryption key (keep the padding). Losing it makes the
# database unreadable, so never delete or rotate this secret casually.
openssl rand -base64 32 | tr -d '\n' | aws secretsmanager put-secret-value \
  --secret-id <store-key-secret> --secret-string file:///dev/stdin

# Embedded IdP session cookie key
openssl rand -base64 32 | tr -d '\n' | aws secretsmanager put-secret-value \
  --secret-id <cookie-key-secret> --secret-string file:///dev/stdin
```

These reach `netbird-server` as `NB_AUTH_SECRET`, `NB_STORE_ENCRYPTION_KEY`
and `NB_IDP_SESSION_COOKIE_ENCRYPTION_KEY` (needs NetBird v0.83.0 or
later), so they never appear in `config.yaml`, on EFS, or in Terraform
state.

### Initial owner (recommended)

Without an owner, the first person to reach `/setup` claims the instance.
`owner_secret_arn` closes that window by creating the owner (upstream
`auth.owner`).

**`auth.owner.password` must be a bcrypt hash, not a password.** NetBird
v0.83.1 passes it to Dex as the stored hash without hashing it, so a
plaintext value makes every login return HTTP 500. NetBird re-applies the
owner on every start, so fixing the hash fixes an existing owner at the next
task start.

The secret is JSON with `email` and `password_hash` (bcrypt). It can also
carry the plaintext `password` so the owner can read it back; the module
never reads that key. Generate both without the password ever appearing on
a command line (`htpasswd` ships with macOS and Apache; `$2y$` and `$2a$`
are the same algorithm):

```bash
python3 - "<owner-email>" <<'PY' | aws secretsmanager put-secret-value \
  --secret-id <owner-secret> --secret-string file:///dev/stdin
import json, secrets, subprocess, sys
pw = secrets.token_hex(24)
out = subprocess.run(["htpasswd", "-niBC", "10", "owner"], input=pw,
                     capture_output=True, text=True, check=True).stdout.strip()
h = out.split(":", 1)[1].replace("$2y$", "$2a$", 1)
sys.stdout.write(json.dumps({"email": sys.argv[1], "password": pw, "password_hash": h}))
PY
```

Only the hash is written to a file: `config-init` appends it to
`config.yaml` on the task's ephemeral storage (encrypted by Fargate,
discarded when the task stops). It is never written to EFS.

## Usage

```hcl
module "netbird" {
  source = "../../modules/netbird_server"

  name   = "netbird"
  domain = "netbird.example.com"

  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.public_subnet_ids
  ingress_security_group_ids = [module.sg_nlb.id]

  cluster_arn  = module.ecs_cluster.cluster_arn
  cluster_name = module.ecs_cluster.cluster_name

  https_target_group_arn = aws_lb_target_group.https.arn
  stun_target_group_arn  = aws_lb_target_group.stun.arn

  auth_secret_arn                 = module.netbird_auth_secret.secret_arn
  store_encryption_key_secret_arn = module.netbird_store_key.secret_arn
  session_cookie_key_secret_arn   = module.netbird_cookie_key.secret_arn
  owner_secret_arn                = module.netbird_owner.secret_arn
  kms_key_arn                     = module.netbird_kms.key_arn

  aws_region = var.aws_region
  tags       = local.common_tags
}
```

## Singleton service

SQLite does not support concurrent writers, so `desired_count` is capped at
1, and deployments are stop-then-start (`deployment_maximum_percent = 100`,
`deployment_minimum_healthy_percent = 0`). Never run two tasks against the
same EFS filesystem.

## Images

All three images are pinned by digest (`netbird_server_image`,
`dashboard_image`, `traefik_image`), following the ADR-034 image-drift
incident. Upgrade by bumping a digest in a PR. A digest can be resolved
without a Docker daemon through the registry API: request a pull token from
`auth.docker.io`, then `HEAD https://registry-1.docker.io/v2/<repo>/manifests/<tag>`
and read `Docker-Content-Digest`.
