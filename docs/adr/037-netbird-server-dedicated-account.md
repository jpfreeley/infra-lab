# ADR-037: Self-Hosted NetBird Server in a Dedicated Account, Torn Down When Idle

## Status

Proposed. Nothing is applied yet. The account creation (`infra/mgmt/org`)
ships as its own, later PR, after the module and live wiring have been
reviewed, because closing an AWS account is manual and slow (90-day
suspension) and so is the one step here that is hard to undo.

## Context

JP wants unattended remote control of an Android tablet with `scrcpy`,
which drives the device over ADB. ADB over TCP gives full control of the
device, so the transport must never be exposed to the internet. It has to
run inside a private WireGuard overlay network.

A hosted overlay (Tailscale) was tried first and works. JP prefers a
self-hosted control plane instead: NetBird
(github.com/netbirdio/netbird), which is open source, WireGuard-based,
has an Android client, and has a documented single-host self-hosted
install. The requirement is that it is positioned and provisioned the same
way as the MemPalace server (ADR-034), and that it tears down to near
zero cost when not in use and comes back up on demand.

### What NetBird's self-hosted server is

Verified against docs.netbird.io (self-hosted quickstart, configuration
files reference, external reverse proxy guide, all updated 2026-11-12) and
the upstream `infrastructure_files/getting-started.sh`:

- Since v0.65.0, one combined container, `netbirdio/netbird-server`, runs
  management, signal, relay and STUN. It listens on plaintext `:80` for
  HTTP/1.1, WebSocket and gRPC over h2c, on UDP `3478` for STUN, and on
  `:9000` for `/health`. TLS is expected to terminate in a reverse proxy
  in front of it.
- A second container, `netbirdio/dashboard`, serves the web UI on `:80`.
- The vendor default puts Traefik in front of both, publishes TCP 443 and
  UDP 3478, and gets certificates from Let's Encrypt via TLS-ALPN-01.
- Identity is an embedded Dex server. The first owner account is created
  through a one-time `/setup` page (or the setup API). No external IdP is
  required.
- State lives in one directory, `/var/lib/netbird`: the SQLite management
  store, the Dex store (`idp.db`), activity events, and keys. Postgres is
  optional and only recommended for multiple management instances.
- The installer generates three secrets: the relay auth secret
  (`server.authSecret`), the datastore encryption key
  (`server.store.encryptionKey`), and a session cookie key. The first two
  can be supplied as `NB_AUTH_SECRET` and `NB_STORE_ENCRYPTION_KEY` from
  v0.83.0. Losing the datastore key makes the existing database
  unreadable.

### Reverse proxy routing NetBird requires

| Path | Protocol |
| --- | --- |
| `/signalexchange.SignalExchange/*` | gRPC, h2c to backend |
| `/management.ManagementService/*` | gRPC, h2c to backend |
| `/relay*`, `/ws-proxy/signal*`, `/ws-proxy/management*` | WebSocket |
| `/api/*`, `/oauth2/*` | HTTP |
| `/*` | HTTP, to the dashboard container |

gRPC streams and relay WebSockets are long-lived. The vendor proxy
templates set read, write and idle timeouts to zero or one day.

### Why the MemPalace front end (ALB + WAF) does not fit

ADR-034 fronts MemPalace with an ALB, WAF and ACM. Three properties of
NetBird break that shape:

1. **STUN needs UDP 3478 reachable from the internet.** The docs state
   it "cannot be proxied through your reverse proxy." An ALB cannot carry
   UDP at all. NetBird can point clients at an external STUN server
   (`server.stuns`) instead, but the docs do not say the embedded
   listener can be turned off, and do not describe peer behavior with no
   reachable STUN.
2. **gRPC must reach the backend as h2c.** The NetBird docs require
   "HTTP/2 (h2c) upstream support" for the gRPC routes. NetBird's docs say
   nothing about AWS load balancers, and whether an ALB gRPC target group
   will speak cleartext HTTP/2 to a target was not verified. If it will
   not, a TLS sidecar would be needed in the task purely to satisfy the
   ALB.
3. **Long-lived streams.** ALB idle timeout tops out at 4000 seconds,
   short of the one-day timeout the vendor templates use.

WAF only attaches to an ALB (or CloudFront, API Gateway, AppSync,
Cognito, App Runner, Verified Access), so dropping the ALB drops WAF.

## Decision

### Layering: same as ADR-034

1. **Portable module, `infra/modules/netbird_server`.** ECS Fargate task
   definition (Traefik, `netbird-server`, `dashboard`), EFS volume for
   `/var/lib/netbird` and Traefik's state, task and execution roles,
   CloudWatch log group, NLB target group attachments. Every input is a
   variable: VPC and subnet IDs, cluster ARN, KMS key ARN, secret ARNs,
   domain, image tags, task size. Nothing hardcodes infra-lab account
   IDs, the domain, or the org layout.
2. **infra-lab live wiring, `infra/live/netbird`.** VPC, ECS cluster,
   NLB, Route53 records, KMS key, Secrets Manager entries, budget.

### Dedicated account: `infra-lab-netbird`

A new account under the Workloads OU, created by the same account-factory
pattern as ADR-031 and ADR-034, with its own service-boundary SCP.

- **Sensitivity.** Whoever controls this control plane can add a peer to
  the overlay and reach every device on it, including ADB on the tablet.
  This is the most sensitive workload in infra-lab and gets the
  tightest boundary.
- **No co-tenancy with shared services.** The MemPalace account also
  hosts the MagNet Legal instance (ADR-034, "MagNet Legal Instance").
  A personal device-access plane should not share an account with a
  service another team uses.
- **Independent lifecycle.** MemPalace idle teardown destroys that
  account's load balancer. Sharing it would cut active remote sessions
  whenever MemPalace went idle.
- **Precedent.** ADR-031 and ADR-034 both give a workload its own
  account when its lifecycle diverges from dev's.

SCP allow-list: `ecs`, `ec2`, `elasticfilesystem`,
`elasticloadbalancing`, `kms`, `secretsmanager`, `iam`, `sts`,
`cloudwatch`, `logs`, `budgets`, `ce`, plus the same baseline services
the MemPalace SCP keeps (CloudTrail, Config, GuardDuty, Security Hub,
Access Analyzer, Organizations read, S3, Service Quotas, Support, SSO).
No `wafv2`, no `lambda`, no `events`.

Account overhead: accounts are free. GuardDuty is auto-enabled for all
org members and Security Hub and Config conformance packs are org-wide,
so the account carries their per-account charges. For a small account
with no always-on resources, expected at roughly $1 to $3 a month.
Config item recording rises somewhat with up/down churn (each cycle
creates and deletes a few dozen resources); that is cents a month at
expected usage.

### Network: public-only VPC, no NAT

`10.0.128.0/20` (next free block after MemPalace in
`docs/networking-cidr-plan.md`), two public subnets for EFS mount target
redundancy, IGW, no NAT Gateway. Same cost lever as ADR-031 and ADR-034.
The task gets a public IP for outbound image pulls only; its security
group accepts ingress from the NLB only.

### Front end: NLB instead of ALB + WAF

A Network Load Balancer with security groups:

- **TCP 443** to Traefik in the task.
- **UDP 3478** to `netbird-server` STUN in the task.

This is the vendor's own supported topology (Traefik in front of the
combined server), with an NLB added in front only to give a stable DNS
target and health checks across up/down cycles. It removes the h2c and
timeout problems entirely, because Traefik is the HTTP/2 hop, exactly as
upstream ships it.

TLS termination, to settle in the implementation spike:

- **Option A (preferred): NLB TLS listener with an ACM certificate**,
  ALPN policy `HTTP2Preferred`, forwarding cleartext to a Traefik
  entrypoint that accepts both h2c (prior knowledge) and HTTP/1.1. Same
  ACM and Route53 DNS validation path as ADR-034, no Let's Encrypt, no
  certificate state to keep.
- **Option B (fallback): NLB TCP passthrough**, Traefik terminates TLS
  with Let's Encrypt (TLS-ALPN-01), ACME state on EFS so a bring-up
  reuses the existing certificate instead of re-issuing. Byte-for-byte
  the vendor default.

**Accepted trade-off: no WAF.** Compensating controls:

- Every NetBird endpoint is authenticated. Peers authenticate with their
  WireGuard keys plus a login or setup key; the dashboard and API sit
  behind Dex.
- The server is up only while in use (below), which shrinks the
  exposure window from always to a few hours a week.
- NetBird's installer supports CrowdSec (`NETBIRD_ENABLE_CROWDSEC`) as
  an in-stack alternative if exposure becomes a concern.
- Admin accounts use long random passwords. The `/setup` page works only
  while no user exists, so anyone who reaches it first can claim the
  instance. The owner account is created immediately after the first
  bring-up, in the same session, before the instance is left running.

### Persistence and secrets

- EFS, encrypted with a dedicated KMS CMK, mounted at `/var/lib/netbird`.
  SQLite, because the service is a single task (desired count capped at
  1, never Spot), so the "no concurrent writers" limit does not apply.
  EFS is never part of the teardown target list.
- Relay auth secret, datastore encryption key and session cookie key are
  generated out of band (`openssl rand -base64 32`) and written straight
  to Secrets Manager with `put-secret-value`. Terraform references ARNs
  only (ADR-023). Injected through ECS `secrets`. The datastore key
  is the one value whose loss destroys data, so its secret keeps the
  default 30-day recovery window and is never part of any teardown.
- `config.yaml` is rendered at task start from a template plus injected
  environment values, so no secret is written to EFS or committed.

### Image pinning

All three images pinned to exact versions (never `latest`), following
the MemPalace image-drift incident (ADR-034, 2026-09-18). Upgrades are
explicit PRs that bump the pin.

### Tear down to zero, bring up on demand

What gets destroyed on `down`: ECS service, NLB, its listeners and
target groups, the Route53 alias. What stays: VPC, cluster, EFS, KMS,
secrets, security groups, ACM certificate. While down the account costs
EFS storage (state is megabytes), the KMS key (about $1 a month), the
secrets (about $1.20 a month for three) and the baseline services.

**Idle detection is a time lease, not traffic.** MemPalace counts
`HTTPCode_Target_2XX_Count` on the ALB. That signal is useless here, for
two reasons:

1. Every enrolled client holds a long-lived management stream open, so
   the server never looks idle while any peer is online, and the tablet
   is online all the time.
2. The actual remote-control traffic is peer to peer over WireGuard (or
   the relay), and only the relay case touches the server at all.

Instead, `up` takes a duration and records an expiry in two repo
variables, `NETBIRD_KEEP_UP_FROM` and `NETBIRD_KEEP_UP_UNTIL`, the same
self-expiring mechanism as MemPalace's protected-uptime window (ADR-034,
2026-08-25). A scheduled check tears the stack down once `now` passes
`UNTIL`. Extending a session is another `up` with a later expiry.

Components, mirroring MemPalace:

- `.github/workflows/netbird-toggle.yml`: targeted apply/destroy, OIDC
  into the management account, then the second hop into the NetBird
  account through Terraform's `assume_role`.
- `.github/workflows/netbird-lease-teardown.yml`: every 15 minutes,
  tears down if the lease has expired. Triggered by both GitHub cron and
  the existing EventBridge Scheduler Lambda pattern in `infra/live/dev`
  (ADR-034, 2026-09-03), since GitHub cron alone was measured drifting
  up to four hours.
- A local wrapper script (`netbird.sh {status|up [duration]|down}`)
  outside this repo, same role as the MemPalace wrapper: switch to the
  right `gh` account, set the lease variables, dispatch the toggle,
  poll for health.

A health check that means "ready" is a 200 from
`/oauth2/.well-known/openid-configuration` through the NLB, which is the
same probe the vendor installer uses.

### Known risk: client re-attachment after a cold start

When the server comes back, the unattended Android client must notice on
its own and re-register its endpoints, with nobody touching the device.
The NetBird client retries the management connection with backoff, but
the maximum backoff on Android is not documented. If it is long, the
first remote session after `up` waits on it. This gets measured on the
real device during the spike. If it is too slow, the fallback is to keep
the server up on a longer standing lease rather than to add an always-on
component.

Note that Android allows one VPN at a time and the client must be set as
the system's Always-on VPN with battery optimization disabled. That is
device configuration, not infrastructure, and is out of scope here.

## Consequences

### Positive

- No third-party control plane holds the keys to the overlay.
- Cost tracks use: roughly $0.06 an hour while up (NLB about $0.023,
  Fargate 0.5 vCPU / 2 GB about $0.03, plus NLCU and EFS I/O), and a few
  dollars a month while down.
- Reuses proven pieces: account factory, VPC module, ECS cluster module,
  KMS module, Secrets Manager module, the lease variables, the
  EventBridge trigger.
- The module is portable the same way `mempalace_server` is.

### Negative

- No WAF, the first internet-facing infra-lab service without one. See
  the compensating controls above.
- Remote access depends on a bring-up first, a few minutes of ECS start
  plus client re-attachment. Not suited to "the device needs help right
  now while I'm away from a terminal" unless a standing lease is set.
- One more AWS account to own, and its creation is hard to undo.
- Two pieces of upstream behavior are unverified and gate the build:
  NLB TLS termination with h2c to Traefik (Option A), and the Android
  client's reconnect delay.

## Implementation Order

1. This ADR (this PR).
2. `infra/modules/netbird_server` and `infra/live/netbird`, plan only.
3. `infra/mgmt/org` account and SCP, separate PR, applied only on
   explicit approval.
4. Spike: apply, settle Option A vs B, create the owner account, enroll
   the Mac and the tablet, measure the reconnect delay after a down/up.
5. Toggle and lease-teardown workflows, wrapper script.
6. Update this ADR with what the spike found, then move it to Accepted.

## References

- ADR-023: Secrets Manager for application secrets
- ADR-030: Compute layer off by default in dev
- ADR-031: Dedicated WorkSpaces account
- ADR-034: Shared MemPalace server, portable module
- NetBird self-hosted quickstart: <https://docs.netbird.io/selfhosted/selfhosted-quickstart>
- NetBird configuration files: <https://docs.netbird.io/selfhosted/maintenance/configuration-files>
- NetBird external reverse proxy: <https://docs.netbird.io/selfhosted/external-reverse-proxy>
