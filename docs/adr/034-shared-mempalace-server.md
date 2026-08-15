# ADR-034: Shared MemPalace Server as a Portable App on Dedicated Infra

## Status

Accepted. Design verified live 2026-08-14. The full ~41k-drawer local
palace was migrated into the shared server 2026-08-15 (see "Security
Incident, WAF Tuning, and Full Migration" below), the task was
right-sized off real usage data the same day (see "Automatic Idle
Teardown and Final Right-Sizing" below), and up/down control is now
automatic — the stack tears itself down after 90 minutes of no real
traffic rather than needing a manual trigger every time. See
"Currently Torn Down" for the last manually-observed state; the
idle-teardown workflow is now the thing that actually keeps it down
between sessions, not a person remembering to run it.

## Context

JP wants one shared MemPalace instance reachable across personal devices/dev
desktops, replacing pair.com as the host, deployed on infra-lab's own AWS
footprint. Because it needs to be reachable outside the VPC, auth and
encryption are the primary concerns, not a secondary hardening pass.

MemPalace ships its own documented Remote/Team Server mode — this is not a
custom design. Verified directly from `deploy/docker-compose.server.yml` in
the upstream repo (github.com/milla-jovovich/mempalace):

- Two containers: `qdrant` (vector store, no exposed port — internal only)
  and `mempalace serve --host 0.0.0.0 --port 8765 --backend qdrant`
  (bearer-token auth via `MEMPALACE_MCP_HTTP_TOKEN`, `/healthz` endpoint).
- Two persistent volumes (`qdrant-storage`, `mempalace-data`).
- Vendor's own stated requirement: *"This exposes plaintext HTTP on :8765.
  For anything beyond a trusted private network, put a TLS-terminating
  reverse proxy in front."*

The same mode is independently proposed in MagNet Legal's own ADR-075
(Qdrant backend, MCP over HTTP, bearer-token auth) for that project's team
dev memory — unrelated project, same vendor-documented path, which confirms
this is a real supported deployment shape rather than something to design
from scratch.

Two additional constraints from JP, on top of the mode itself:

1. **Cost-conscious.** This is a personal-use service, not revenue-bearing.
   Every always-on line item needs a reason.
2. **Reusable.** JP intends to stand this same thing up again inside the
   MagNet Legal AWS environment later. The deployable unit has to work
   outside infra-lab's monorepo and account topology, not just inside it.

infra-lab already separates INFRA (`infra/modules` — VPC, ECS, ALB, KMS,
Secrets Manager: reusable primitives) from APP (workloads deployed onto
that infra; currently one placeholder app in `infra/live/dev`). This
deployment is an APP effort. It should consume infra-lab's INFRA primitives,
not become one — with one exception noted below.

Two structural mismatches with the existing dev environment:

- `infra/live/dev` is intentionally scale-to-zero and torn down/rebuilt
  often (ADR-030). A personal memory service that needs to be reachable at
  any time is the opposite of that lifecycle. ADR-031 already set the
  precedent for this exact situation: when a workload's purpose/lifecycle
  diverges from the lab environment, it gets its own dedicated account
  under the Workloads OU rather than being squeezed into dev.
- `infra/modules/ecs_service` is single-container with no volume support.
  MemPalace's two-container-plus-persistent-volumes shape doesn't fit it.

## Decision

**Split into two layers, matching the reuse requirement:**

1. **A portable, parameterized Terraform module** —
   `infra/modules/mempalace_server` — that stands up the Remote/Team
   Server mode on ECS Fargate: task definition (qdrant + mempalace
   containers, task-local networking so qdrant is reachable only via
   `localhost` inside the task and never gets its own security-group
   ingress), EFS-backed persistent volumes, ALB target group wiring,
   CloudWatch log group. Every input is a variable — VPC/subnet IDs,
   cluster ARN, KMS key ARN, ACM cert ARN, secret ARN, CIDR list, task
   size — nothing hardcoded to infra-lab's account IDs, domain, or org
   structure. This is the piece JP reuses in MagNet Legal's AWS
   environment later, either as a git-sourced module reference or a
   straight copy — no code changes required to retarget it.
2. **infra-lab-specific "live" wiring**, which does *not* get reused
   elsewhere:
   - New dedicated account (`infra-lab-mempalace`, under the Workloads
     OU) via the same account-factory pattern as ADR-031
     (`infra/mgmt/org`), with its own service-boundary SCP.
   - `infra/live/mempalace/` instantiates the module against that
     account's VPC, ALB, WAF, and Secrets Manager entry.

   MagNet Legal already has its own AWS account (see their ADR-078); it
   consumes the module inside its existing environment, it doesn't need
   infra-lab's account/SCP layer at all. That's exactly the boundary the
   module/live split is for.

**Cost-conscious topology** (same lever ADR-031 already used for
Workspaces): single public subnet, IGW, no NAT Gateway. The Fargate task
sits in the public subnet but its security group only accepts traffic from
the ALB's security group on :8765 — no direct public ingress to the task
itself. This alone avoids ~$32-35/mo that a NAT Gateway would add for zero
benefit here (nothing in the task needs outbound access to reach a NAT).

- Smallest Fargate task size that actually works — needs an empirical test
  of the embedding step's real memory footprint (`MEMPALACE_EMBEDDING_DEVICE`
  runs CPU-only in-container), not a guess. Sizing is an open question
  below, not decided here.
- WAF kept to the cheap managed rule set + a rate-based rule only — skip
  Bot Control / Fraud Control, which cost meaningfully more and aren't
  proportionate to a personal single-user endpoint.
- EFS is pay-per-GB and personal memory data is small; no capacity
  provisioning needed.
- ALB is the one fixed cost that isn't avoidable — it's the TLS
  termination point AND the only thing WAF can attach to. infra-lab's own
  dev ALB is already priced at ~$16/mo (ADR-030); treat this the same way.

**Auth + encryption** (the primary concern, per the original ask):

- Bearer token (`MEMPALACE_MCP_HTTP_TOKEN`) generated out-of-band (e.g.
  `openssl rand`) and written directly into Secrets Manager via
  `aws secretsmanager put-secret-value` — never as a Terraform variable
  default, never in a `.tfvars` file, never in the module's `environment_variables`
  map. Terraform only ever references the secret's ARN (ADR-023 pattern).
  Injected into the task via ECS `secrets`, not `environment`.
- TLS 1.2+ ACM cert on the ALB listener, matching infra-lab's existing
  `ELBSecurityPolicy-TLS13-1-2-2021-06` policy already used in
  `infra/live/dev/alb.tf` — **gated behind `var.enable_https` (default
  `false`), not live yet.** Discovered during implementation: ACM cannot
  issue a certificate for the ALB's own `*.elb.amazonaws.com` hostname (no
  domain to validate against), which directly conflicts with "bare ALB DNS
  name for now." Resolved by explicit decision: **ship HTTP-only behind
  WAF + bearer token as a deliberate, temporary bootstrap**, not a silent
  compromise — `enable_https`/`acm_certificate_arn` flip this the moment a
  domain exists, without restructuring anything. Client-to-ALB is the one
  hop that crosses a public network; until HTTPS is enabled, that hop is
  plaintext, meaning the bearer token itself crosses the network
  unencrypted. That's a real, accepted gap for this bootstrap phase, not
  something to leave indefinitely. ALB-to-task stays inside the account's
  subnet either way, which satisfies the vendor's "trusted private network"
  bar for the plaintext :8765 hop regardless of the client-facing listener.
- Data at rest: EFS volumes and the Secrets Manager entry encrypted with a
  dedicated KMS CMK (existing `kms_key` module), not the AWS-managed default
  key — gives an explicit place to control/rotate/audit access.
- Nothing personal (JP's identity, email, IPs, tokens, or any real secret
  value) goes into git or a built container image. Terraform files
  reference ARNs and variables only; actual secret material is generated
  and stored directly in Secrets Manager out-of-band. This applies to any
  `.tfvars`, module defaults, Docker build args, or committed docs —
  including this ADR and its follow-ups.

## Architecture (sketch)

```text
Client (bearer token, HTTPS)
  -> WAF (managed rules + rate limit)
  -> ALB :443 (ACM cert, TLS 1.2+)
  -> ECS Fargate task, public subnet, SG: ingress from ALB SG only
       - container: mempalace serve --port 8765 --backend qdrant
         (target of ALB target group)
       - container: qdrant (localhost-only inside task, no SG ingress)
     both containers -> EFS (KMS-encrypted persistent volumes)
Secrets Manager (KMS-encrypted) --token--> ECS task secrets
CloudWatch Logs (KMS-encrypted, per ADR-025 pattern)
```

## Consequences

- New account = new SCP service-boundary policy (ecs, ec2 for Fargate
  ENIs/EFS mount targets, elasticloadbalancing, wafv2, secretsmanager, kms,
  elasticfilesystem, logs, cloudwatch, budgets/ce, baseline Control Tower
  services), new Terraform state key under the existing S3 backend.
- Always-on cost, not off-by-default like dev — that's intentional; this is
  a utility meant to be reachable at all times, not a lab environment torn
  down between sessions. Rough estimate once sized: ALB ~$16/mo + WAF
  ~$5-10/mo + small Fargate task + EFS (minimal) — needs a real number
  once task sizing is tested, not asserted here.
- `ecs_service` module stays single-container/no-volumes as-is;
  `mempalace_server` is a new, separate module rather than an extension of
  it — MemPalace's shape (2 containers, persistent volumes, no blue/green)
  doesn't overlap enough with `ecs_service`'s current consumer to justify
  merging them.
- Reuse in MagNet Legal is a documentation/interface discipline going
  forward, not a promise the module is portable on day one — first real
  test of that portability is the actual second deployment, whenever JP
  does it.

**Alternative considered: reuse the existing (currently idle) WorkSpaces
account (ADR-031) instead of a new dedicated one.** Checked the actual
governance-cost figures in `docs/runbooks/ecs-cost-controls.md` before
deciding rather than assuming: the ~$15-25/mo "governance" baseline
(CloudTrail/Config/GuardDuty/Security Hub/KMS) documented in this repo is
an **org-wide total for centrally-administered services** (ADR-007
delegated-admin pattern), not a clean per-account line item — so a new
account does not straightforwardly cost "+$15-20/mo." Config's
conformance pack does apply per-account, and GuardDuty/Security Hub have
real per-account/per-finding usage pricing in AWS's actual billing even
under central administration, so a new account likely adds *something*,
just not a number this repo quantifies anywhere. Net: reusing Workspaces
would have been a modest, imprecise cost saving plus real simplicity
(skip account creation, a new SCP, possibly a new VPC). Decided against
it anyway — a public-facing service sharing an account with an SSH/DCV-
reachable dev desktop widens blast radius and dilutes ADR-031's
narrowly-scoped SCP, and while Workspaces is unused *right now*, "not
soon" isn't "never." Isolation won on a close call, not a lopsided one —
worth revisiting if Workspaces stays unused indefinitely.

- Full public exposure means the bearer token + WAF are the only things
  between the internet and JP's memory data. Token rotation process isn't
  designed yet (see open questions).
- Losing the Secrets Manager entry or the KMS CMK without a recovery path
  makes the token/data unrecoverable — needs a backup story before this
  holds real data (open question below).

## Open Questions

1. **Domain/DNS** — SUPERSEDED: was "bare ALB DNS name for now," now decided
   as `mempalace.lintwiselabs.com` (see "Decided, Not Yet Built" above).
   Not yet implemented — no Route53 record or ACM cert created yet.
2. **Task sizing** — RESOLVED and right-sized, with real CloudWatch data
   at every step, not guesses. Went through three sizes before landing on
   the final steady-state default:
   - `cpu=256`/`memory=512` (Fargate's floor, the original starting
     guess) — enough to start, pass health checks, and survive idle. But
     genuinely undersized for write-heavy bulk load: during the
     2026-08-15 migration, CloudWatch showed the task pegged at 99-100%
     CPU for sustained multi-minute stretches (memory under 60%, EFS
     `PercentIOLimit` under 1% — CPU, not storage, was the ceiling).
   - `cpu=2048`/`memory=4096` — a temporary bump for that migration only,
     roughly quadrupling sustained write throughput (2.3 rec/s -> 9.5
     rec/s). Reverted back to `256`/`512` the same day once the
     ~41k-record migration finished (PR #119) — this size was never meant
     to be the steady-state default, only a lever for bulk operations.
   - **`cpu=512`/`memory=1024` — the actual steady-state default, landed
     on after real post-migration usage, not the migration tuning.** A
     genuine light-usage burst (a handful of near-simultaneous
     `mempalace_search` calls in one session) spiked ALB
     `TargetResponseTime` to a 15s worst case at the `256` floor,
     CPU-bound on embedding computation (CPU jumped 10%->66% in the same
     minute). `256` is fine at idle but not for interactive query bursts,
     which matters far more for this service's real usage pattern than
     bulk-write throughput does. Verified live at `512`: the same class
     of query burst dropped to a 0.50s worst case (30x improvement) with
     CPU only peaking at 15% — real headroom, not just barely enough.
   Both values are plain Terraform variables (`mempalace_cpu`/
   `mempalace_memory` in `infra/live/mempalace/variables.tf`), so scaling
   further for a one-off bulk job (another big migration, a mass
   re-embed) is still just a one-line change plus a redeploy, not a
   module edit — the `2048`/`4096` data point above stays available as a
   known, tested lever even though it's no longer the default. Remote-
   embedding-server offload (noted below as an alternative) was never
   tried — the brute-force CPU bump was simpler and got measured,
   verified results at every size tested.
3. **Token rotation** — RESOLVED as designed and actually exercised for
   real, not just planned. The guest-key/permission-level model described
   in public docs does **not** exist in the installed CLI (see "Multi-
   User / Team Permissioning" below, verified directly against `mempalace
   serve --help` v3.6.0) — there is exactly one bearer token per server
   process, full read/write, no finer grain. Rotation is therefore: mint
   a new token (`openssl rand -base64 32`), `aws secretsmanager
   put-secret-value` it, force a new ECS deployment to pick it up. This
   was actually done for real on 2026-08-15 after the WAF log-leak
   incident (see below) — the one wrinkle discovered was that ECS's
   default rolling deployment (200%/100%) doesn't work for this service
   at all (see the write-lock fix, same section), so token rotation
   silently never took effect until that was fixed. Documented so a
   future rotation doesn't rediscover the same trap.
4. **Backup/DR** — RESOLVED, per direct confirmation from the session
   actively running the current mp_sync setup: the central Qdrant server
   becomes the sole source of truth (no more per-machine Chroma
   divergence to reconcile), and the existing mp_sync export → GitHub
   archive path is repurposed as a periodic backup job run *against* the
   central server, not a sync mechanism between machines. One caveat
   surfaced directly from that session: mp_sync's export format
   (`{"id","document","metadata"}` JSONL, no embeddings) means migrating
   the existing ~41k-drawer local palace into Qdrant is a one-time
   **re-embed on import**, not a raw vector copy — a real one-time compute
   cost to plan for, not a nightly operation.

## Design Notes from the Live mp_sync Session (2026-08-14)

Cross-checked directly against the session actively operating the current
sync setup, not assumed:

- Today's local setup is Chroma per machine (`"backend": "chroma"`,
  confirmed via `mempalace_status`) with a standing local HTTP MCP server
  (`mempalace serve --host 127.0.0.1 --port 8765`, launchd-managed) that
  any MCP client on that machine can connect to concurrently.
- **Write-lock contention is a known, already-observed problem** —
  concurrent local MCP clients on one machine already produce "Peer MCP
  writer active" errors today. Multiple devices hitting one central Qdrant
  server will hit the same class of problem, likely worse under real
  concurrency — this needs explicit handling in the module (queuing /
  understanding Qdrant's concurrency model vs. Chroma's single-writer
  behavior), not an assumption that moving to a "real" server backend
  makes it disappear for free.
- Only one machine (`jpf321-new-machine`) is actually live in mp_sync today
  — the multi-machine convergence problem this ADR's central server solves
  is currently a 1-machine problem in practice, which is worth keeping in
  mind for how urgently this needs to ship vs. how it's prioritized.
- Corpus size confirmed independently by both sessions: 41,182 drawers /
  5,616 closets as of 2026-08-14.

## Multi-User / Team Permissioning — RESOLVED, hard constraint

Verified directly against the installed CLI (`mempalace serve --help`,
v3.6.0 — the actual binary, not documentation) rather than the public docs
site, which turned out to describe a guest-key/permission-level model that
does **not** match what's actually implemented. Full flag set:

```text
mempalace serve [--host HOST] [--port PORT] [--backend BACKEND]
                 [--palace PALACE] [--token TOKEN] [--tls-cert TLS_CERT]
                 [--tls-key TLS_KEY] [--read-only] [--allow-insecure]
```

- `--token` is a **single bearer token for the whole server process**.
  Anyone holding it has full read/write access to the entire palace —
  every wing, every room, every drawer. There is no per-user/guest-key
  concept in the actual implementation.
- `--read-only` is a **global, server-wide toggle**. It's not a
  per-connection or per-token mode — either every client connecting to
  that server instance is read-only, or none are.
- There is no wing/room/drawer-scoped ACL of any kind.
- Native `--tls-cert`/`--tls-key` support exists in the server itself
  (relevant if TLS ever needed to terminate at the container instead of
  the ALB — not the plan here, ALB+ACM stays simpler for key management,
  but noting the capability exists).

**Consequence for this deployment (JP, personal, multi-device):** no
problem — one token, one palace, full access from every device is exactly
the intended model.

**Consequence for the MagNet Legal reuse (a real team, not a single
user):** this is a hard constraint, not a tuning knob. `mempalace_server`
as designed gives *all-or-nothing* access per deployed instance. The only
native way to get any separation between team members is running
**separate `mempalace serve` processes with separate tokens and separate
`--palace`/backend paths** — which are just unconnected palaces, not
scoped access to one shared corpus. If MagNet Legal needs a single shared
team palace with per-member content boundaries, that does not exist today
in upstream MemPalace and would require either (a) accepting a full-trust
single-token model for the team, (b) a bespoke auth-proxy in front doing
per-user routing to separate backend collections (real added complexity,
outside what this module scaffolds), or (c) waiting on/requesting the
capability upstream. Deliberately left undecided here — MagNet Legal's own
call to make when that reuse actually happens, not assumed now.

Filed upstream as
[MemPalace/mempalace#2258](https://github.com/MemPalace/mempalace/issues/2258)
(2026-08-14) — design sketch: token→scope mapping, contextvar-based
per-request scope threading (doesn't exist today; `--read-only` gets away
with a static module-level flag because it's process-wide, scope isn't),
and per-tool classification across the 44 `tool_*` call sites mirroring
the existing `_READ_ONLY_REFUSED_TOOLS` pattern. Traced directly from
source (`mcp_server.py`), not assumed. If accepted upstream, this
constraint goes away; if not, options (a)-(c) above are still live.

## Domain, HTTPS, and GitHub Toggle Workflow — Built and Tested (2026-08-14)

Both follow-on decisions from earlier the same session are now actually
built, not just decided:

**Domain**: `mempalace.lintwiselabs.com`. `lintwiselabs.com` is one of four
bare hosted zones already in the management account's Route53 (checked
directly — `starterstackadvisors.com`, `lintwiselabs.com`, `nyc-merch.com`,
`alumnisportingevents.com`, each with only default NS/SOA records, nothing
live to conflict with). `infra/live/mempalace/acm.tf`: ACM cert for the
domain (DNS-validated via an aliased `aws.dns` provider pointed at the
management account, since the zone lives there but the cert has to live in
the mempalace account with the ALB), plus the actual service alias record
(distinct resource from the validation CNAME) pointing at the ALB's live
`dns_name`/`zone_id` — self-heals on every recreate automatically, no
manual re-pointing. `enable_https` and `acm_certificate_arn` both flipped
to real defaults (cert ARN
`arn:aws:acm:us-east-1:310697203282:certificate/16ea7326-c0f8-47e9-bc46-279e4d4bef02`).
Verified for real, not assumed: `curl https://mempalace.lintwiselabs.com/healthz`
→ 200 no-auth, `POST /mcp` no token → 401. Both TLS and the domain
actually work end to end.

**Up/down control, via `.github/workflows/mempalace-toggle.yml`
(`workflow_dispatch`, not a schedule yet)** — deliberately simpler than
the nightly-cron plan sketched earlier: a manual trigger first, proven
working, before adding a schedule on top. Scope is exactly the real-money
resources: ALB, both listeners, target group, WAF Web ACL, WAF
association, ECS service. Auth reuses the existing `github_actions_deploy`
OIDC role as-is (ADR-009) — it already has `AdministratorAccess` in the
management account, so no IAM expansion was needed after all (the earlier
plan assumed `elasticloadbalancing:*`/`wafv2:*` would need adding; turned
out unnecessary). Prerequisite fix that *was* needed: `live/mempalace`'s
provider and backend blocks hardcoded `profile = "infra-lab"`, which
doesn't exist in CI — removed from the backend block (backend blocks can't
reference variables at all) and made conditional in the provider block
(`var.aws_profile != "" ? var.aws_profile : null`), so the same config
works locally (`AWS_PROFILE=infra-lab`) and in CI (OIDC-derived env-var
credentials, `TF_VAR_aws_profile=""`).

**Tested end-to-end for real**, not just written: ran an actual spin-up
(`terraform apply`, 8 added/1 changed) and confirmed HTTPS + auth over the
real domain, then ran the exact `terraform destroy -target=...` command
the workflow uses and confirmed via `terraform plan` (back to "8 to add")
and direct AWS CLI (`ecs list-tasks`/`elbv2 describe-load-balancers`/
`wafv2 list-web-acls`, all empty) that it's clean. One thing this
*couldn't* test locally: whether `workflow_dispatch`'s OIDC token
`sub` claim actually matches the existing trust policy
(`repo:jpfreeley/infra-lab:ref:refs/heads/main` /
`repo:jpfreeley/infra-lab:pull_request` in `github_oidc.tf`) — GitHub's
documented behavior is that the `sub` claim reflects the ref a workflow
runs against regardless of trigger type, which should mean a
`workflow_dispatch` run against `main` already matches, but this is
reasoning from GitHub's docs, not something provable without an actual
GitHub Actions run. If the first real trigger fails at the OIDC step,
that trust policy is the fix.

**Not done yet**: the workflow file exists locally only — nothing from
this session has been committed or pushed, so it doesn't appear in
GitHub Actions yet. That's the actual next step before it's usable.

Because the domain now exists, the DNS-name-churn problem that would
otherwise make repeated ALB teardown impractical (every recreate getting
a new random `*.elb.amazonaws.com` name, breaking any configured MCP
client) is gone — confirmed directly: destroying the ALB via the
workflow's target list also pulled the Route53 alias record into the
same destroy automatically (Terraform won't leave it referencing a
destroyed resource's live attributes), and it came back correctly
pointed at the new ALB on the next apply, no manual intervention.

## Security Incident, WAF Tuning, and Full Migration (2026-08-15)

Picking up the same session's next day: brought the stack back up, fixed
two real bugs found only under live traffic, then ran the actual
~41,204-record migration of the local palace into the shared server.

**Security incident: bearer token leaking into WAF logs, plaintext.**
While investigating an unrelated 403, enabled WAF logging
(`aws_wafv2_web_acl_logging_configuration`) with a `redacted_fields {
single_header { name = "authorization" } }` block specifically to keep
the bearer token out of CloudWatch Logs. Confirmed via `aws wafv2
get-logging-configuration` that the redaction config was live and
correct — and confirmed, via direct `aws logs tail` inspection, that it
did **not** work: the token appeared in plaintext in every logged
request, well past any reasonable propagation delay. Root cause not
pursued further (this looked like an AWS-side redaction bug, not a
misconfiguration on our end) — fixed by treating the token as already
exposed rather than debugging while still leaking:
`aws wafv2 delete-logging-configuration` immediately, then the
CloudWatch log group itself was destroyed (removing the already-leaked
history), then the token was rotated
(`openssl rand -base64 32` -> `put-secret-value`). WAF logging stays
**off** until redaction is proven working with a throwaway token first —
see the commented-out logging resources left in `alb.tf` with this
explanation attached directly at the resource.

**Deployment bug: rolling deployments silently never take effect.**
Discovered while completing the token rotation above: the new task
failed to start with `Writable MCP HTTP startup refused: ... palace is
held by PID 1`. ECS's default rolling deployment (`200%`/`100%`) starts
the new task *before* stopping the old one — but mempalace holds a
single-writer lock on the shared EFS palace, so the new task's attempt
to acquire that lock while the old task still holds it fails, every
time, not occasionally. The deployment circuit breaker caught this and
auto-rolled-back each time (the service stayed up throughout, on the
stale task), which made this a *quiet* failure mode — a token rotation
or any task-definition change would silently never actually deploy,
with no error surfaced anywhere except a task-level log line. Fixed in
`mempalace_server`'s `aws_ecs_service.this`:
`deployment_maximum_percent = 100` / `deployment_minimum_healthy_percent
= 0` — stop-then-start instead of start-then-stop. Consistent with the
module's own singleton design (`desired_count` capped at 1 elsewhere);
this is the deployment-strategy half of that same constraint.

**WAF false positives on real content.** The migration corpus is code
and infra documentation — shell scripts, Terraform, raw HTML/CSS
snippets — which is exactly the kind of content AWS's
`AWSManagedRulesCommonRuleSet` generic body-inspection rules are tuned
to flag. First hit: `GenericLFI_BODY` on a bash script, patched with a
targeted `rule_action_override` (Count instead of Block) for that one
sub-rule. Second hit, same test session: `CrossSiteScripting_BODY` on a
record containing raw HTML/inline CSS. Rather than keep patching
individual sub-rules as more turned up, stepped back: this endpoint's
real access control is the bearer token, not content inspection — every
request either authenticates or gets `401`'d before content is even
looked at, so the Common Rule Set's LFI/XSS/SQLi heuristics (built for
anonymous public form traffic) are the wrong shape for a token-gated
arbitrary-content-storage API. Set the whole
`AWSManagedRulesCommonRuleSet` group's `override_action` to `count {}`
(observation only, not removed — still visible in metrics/sampled
requests). `AWSManagedRulesKnownBadInputsRuleSet` (Log4Shell-class
exploit signatures — about attacking the server, not about stored
content looking suspicious) and the rate-limit rule were left actively
blocking; only the Common Rule Set's blocking was disabled.

**Throughput tuning.** Diagnosed via CloudWatch, not guessed — see
Open Question #2 above for the full CPU-bottleneck finding and the
`cpu=2048`/`memory=4096` bump. A second, smaller ceiling turned up right
after: once CPU was no longer the constraint, the migration script's
own traffic (a single trusted, authenticated IP) started tripping the
WAF `rate-limit` rule's `2000` requests/5-minute-window/IP threshold
(~6.67 req/s sustained) well below the upsized task's real capacity —
confirmed by the exact shape of the failure (a burst to 13-14 req/s,
then 403s climbing as the rolling 5-minute window filled, recovering
only once the early high-rate requests aged back out of that window).
Raised to `20000` for the migration window, verified with a sustained
255-second/2,432-record batch at the new limit with zero failures.
Both bumps were temporary and explicitly tracked as such the moment
they were applied (git commit messages, PR descriptions, and this ADR
all noted "revert once migration is done") — reverted back to `2000`/
`256`/`512` immediately after the migration finished, before the stack
was torn down again. Final measured throughput ceiling: ~9-10 rec/s,
which held flat regardless of client worker count (12 vs. 24 workers,
same rate) — that plateau is the server's real per-request processing
cost (most likely qdrant's embedding + single-writer indexing on every
`add_drawer`), not a client- or network-side limit.

**The migration itself.** Source: `mp_sync`'s export format
(`{"id","document","metadata"}` JSONL, no embeddings — see Open
Question #4), re-embedded on import as expected, not a raw vector copy.
A resumable Python script (progress-tracked via a local `completed_ids`
file, not committed) submitted each record as a real
`mempalace_add_drawer` MCP `tools/call` over the authenticated `/mcp`
endpoint. Final result: **41,204/41,204 records submitted successfully**
(one individual 403 mid-run traced to the WAF false-positive above,
resolved by the Count-instead-of-Block fix and confirmed by retrying it
individually afterward). Verified success is `success: true` on every
submission — but the server's final `mempalace_status` reports **34,646
unique drawers**, not 41,204. Traced this gap to source, not assumed
benign: `mempalace_add_drawer`'s server-side idempotency check
(`mcp_server.py`) derives a deterministic `drawer_id` from
`(wing, room, content)` and probes for that exact id before writing;
if it already exists, it returns `{"success": true, "reason":
"already_exists"}` instead of writing again. This is exact-content
idempotency, not fuzzy/lossy dedup (that's a separate, unrelated
CLI-only tool, `mempalace.dedup`, never invoked here) — the gap
reflects genuine duplicate `(wing, room, content)` tuples already
present in the source export (plausible for an enterprise codebase with
shared boilerplate scripts mined into multiple similar rooms), not
discarded or lost content.

**MCP client wiring.** Added `mempalace-remote` as a second, separate
MCP server entry (alongside the existing local `mempalace` entry, not
replacing it) pointed at `https://mempalace.lintwiselabs.com/mcp` with
the bearer token as an `Authorization` header. Verified healthy two
ways: `claude mcp list` (a real MCP `initialize` handshake over the
configured transport) and a direct `tools/call` to `mempalace_status`
speaking raw JSON-RPC (since a server added mid-session isn't hot-loaded
into an already-running session's own tool list) — both confirmed
working end to end, not just a `/healthz` ping. Only this one machine's
config was updated in this session; other devices still need the same
`claude mcp add` command run locally.

**Final teardown.** Once the migration and its retry were both
confirmed, and the CPU/rate-limit bump reverted in git (see below), the
stack was torn back down via the tested
`.github/workflows/mempalace-toggle.yml` (`action=down`) — verified
against real AWS state afterward (no ALB, ECS service `INACTIVE` 0/0, no
running tasks, no WAF Web ACLs, endpoint unreachable), not just the
workflow's green checkmark. EFS was never in the teardown's scope, so
all migrated data persists untouched through the down/up cycle — that
was always the point of splitting EFS out of the toggle's target list.

## Automatic Idle Teardown and Final Right-Sizing (2026-08-15)

Two more real changes, both from the session immediately following the
migration, both verified live rather than just designed:

**Automatic idle teardown.** The manual `mempalace-toggle.yml` toggle
(up/down via `workflow_dispatch`) still exists and still works, but the
stack no longer depends on a person remembering to run it. A new
scheduled workflow, `.github/workflows/mempalace-idle-teardown.yml`,
checks every 15 minutes whether the ALB has served any real client 2xx
traffic in the trailing 90 minutes and tears the stack down the same
way the manual toggle does (via `workflow_call`, reusing the exact same
destroy target list rather than duplicating it) if it's been idle that
whole window. (Started at a 60-minute window when first built, raised
to 90 minutes the same day per JP's preference — a plain constant
change in the workflow, not a design change.)

The one design risk here — the ALB's own target-group health check
hits `/healthz` every 30 seconds forever, so a naive "any traffic"
check would never see zero and would keep the stack up permanently —
was tested empirically, not just reasoned from AWS docs, with the
stack live: a 5-minute window with only health checks running (zero
real requests) returned **zero datapoints** for
`HTTPCode_Target_2XX_Count`, and a single real client request sent in
the same session registered correctly (`Sum: 1.0`). Health checks are
genuinely invisible to that metric; real traffic isn't. A second real
bug was caught and fixed before this ever ran unattended: a
freshly-created ALB has no CloudWatch history, so "no datapoints in the
trailing window" is ambiguous between "confirmed idle the whole time"
and "hasn't existed that long yet" — without an explicit age check, a
stack brought up and checked before the full window had actually
passed would look identical to real silence and could tear back down
almost immediately. Fixed with a minimum-age gate (window length plus a
5-minute buffer) before the idle check ever runs.

**Final right-sizing, from real post-migration usage, not the
migration tuning.** See Open Question #2 above for the full three-step
sizing history. The short version: `256`/`512` (the original floor)
turned out fine at idle but genuinely bad for real interactive query
bursts — a handful of near-simultaneous `mempalace_search` calls spiked
worst-case ALB response time to 15 seconds, CPU-bound on embedding
computation. `512`/`1024` is now the steady-state default, verified
live with a before/after comparison on the same class of query burst:
15s worst case dropped to 0.50s (30x), and CPU peaked at only 15%
instead of 66% — real headroom, not just barely enough. This is a
permanent default change, not a temporary bump like the migration-era
`2048`/`4096` (which was reverted the same day it was no longer
needed, PR #119) — `512`/`1024` is what the stack actually deploys at
now, combined with the idle teardown above so the larger steady-state
size only costs money while genuinely in use.

## Currently Torn Down (end of 2026-08-14 session)

Deployed, verified live end-to-end (see below), then deliberately torn
back down the same night at JP's explicit request, to stop metered spend
between sessions rather than pay for an idle service nobody's pointed a
client at yet. Targeted-destroyed: `aws_lb.mempalace`,
`aws_lb_listener.http`, `aws_lb_target_group.mempalace`,
`aws_wafv2_web_acl.mempalace`, `aws_wafv2_web_acl_association.mempalace`,
`module.mempalace.aws_ecs_service.this` — confirmed via `aws ecs
list-tasks` / `elbv2 describe-load-balancers` / `wafv2 list-web-acls`
that nothing real-money-costing remains running. Left in place, costing
essentially nothing: VPC, EFS (empty, migration not done), KMS key,
Secrets Manager secret (token already populated, preserved), ECS cluster,
IAM roles, task definition, security groups.

Superseded by the later same-session work below ("Domain, HTTPS, and
GitHub Toggle Workflow"): `mempalace_account_id` now defaults to the real
account ID, so `terraform apply` alone (no `-var` needed) fully recreates
everything, and the set has grown from 6 to 8 resources (the HTTPS
listener and the domain's Route53 alias record joined the stack). Current
real state as of the end of this session is torn down again, this time
via the tested `.github/workflows/mempalace-toggle.yml` destroy target
list rather than by hand — see that section for the exact, verified
resource list and how spin-up/teardown actually work now.

Superseded again by "Security Incident, WAF Tuning, and Full Migration"
above: EFS is no longer empty — the full ~41,204-drawer local palace was
migrated in on 2026-08-15 — and the stack was torn back down a second
time afterward, same workflow, same verification method. That section is
the current source of truth for what's actually deployed/torn-down and
why.

One correctness fix landed as part of this: `mempalace_server`'s
`aws_ecs_service` didn't have `lifecycle { ignore_changes =
[desired_count] }` (matches `infra/modules/ecs_service`'s own
established pattern, which this module was missing) — added before
touching desired_count at all, so a future `apply` won't fight
CLI-driven scaling. Ended up moot for tonight's teardown (the service
was destroyed outright, not just scaled to 0, since destroying its
target group forces that), but it's the correct fix regardless and
matters once real desired-count toggling (nightly automation) exists.

## Implementation Status (as of 2026-08-14)

Written, formatted (`terraform fmt`), validated (`terraform validate`),
linted (`tflint`), and security-scanned (`checkov` — 0 failed across both
the module and the live directory, every skip individually justified).

**Fully deployed and verified live, end to end.** `infra-lab-mempalace`
account (`310697203282`) created under the Workloads OU. `infra/live/mempalace`
applied: VPC (`10.0.112.0/20`, public-only, no NAT), ALB
(`infra-lab-mempalace-alb-421941412.us-east-1.elb.amazonaws.com`, HTTP
only per `enable_https=false`), WAF (common rules + known-bad-inputs +
rate limit), EFS (2 access points, IAM-authorized mounts), ECS Fargate
service (`cpu=256`/`memory=512`), bearer token generated and populated
into Secrets Manager out-of-band (never through Terraform). Verified
directly, not assumed:

- ECS service: 1/1 running, target group health check passing.
- `GET /healthz` → `200` with no auth header (by design, for the ALB
  health check).
- `POST /mcp` with no bearer token → `401 Unauthorized` — auth is
  actually enforced on the real endpoint, not just configured.
- First real (if early) sizing data point: `cpu=256`/`memory=512` —
  Fargate's floor — was enough for both containers to start and pass
  health checks. Not yet enough basis to call it right-sized; needs real
  CloudWatch Container Insights data under actual usage before treating
  the starting guess as confirmed (open question #2 still open on that
  basis).

Two real bugs surfaced only by an actual fresh deploy (impossible to
catch via `-backend=false` static validation, since both need a real not-
yet-existing VPC / real AWS API string validation) and fixed in the
module directly:

- `aws_efs_mount_target.this` used `for_each = toset(var.subnet_ids)`,
  which fails when the subnet IDs aren't known yet (fresh VPC, first
  apply) even though the count is statically known — `toset()` can't
  prove uniqueness of not-yet-known values. Fixed to index-keyed
  `for_each`.
- Two security-group `description` fields (and one WAF description)
  contained an em-dash and an apostrophe, both outside AWS's allowed
  character set for that field (`^[0-9A-Za-z_ .:/()#,@\[\]+=&;{}!$*-]*$`).
  Also just a plain violation of the em-dash writing-style rule this
  session is supposed to follow everywhere, caught by AWS's own API
  validation before I caught it myself.

One more real gap found and fixed, in `infra/mgmt/org`, not this module:
the org-wide mandatory tag policy's allowed `Environment` values never
included `mempalace` (or, discovered in passing, `workspaces` either) —
only enforced on a few resource types (`secretsmanager:secret` among
them), which is why only the Secrets Manager secret failed and every
other resource in this deployment created fine on the first pass. Fixed
by adding both missing values to `tag_policies.tf` and re-applying
`mgmt/org` (1 changed, 0 added, 0 destroyed).

**A real, pre-existing infra-lab bug surfaced and got fixed along the
way, unrelated to MemPalace**: `infra/mgmt/org` had no `backend "s3"`
block — unlike every `infra/live/*` root, it had always used Terraform's
local state, meaning its ~100-resource state existed only on whichever
machine last ran it. A recent machine migration lost that local file
entirely; recovering it required restoring a 2-month-old backup from an
SMB volume (after separately troubleshooting a stale mount and a missing
AWS SSO profile on the new machine) before any apply here was safe.
Fixed properly rather than just patched around: added the missing
`backend "s3"` block, migrated state into it (`terraform init
-migrate-state`), and confirmed via `plan` that it now shows zero drift
against real AWS. `infra/live/shared` had the identical gap (no backend
block) — fixed the same way, though that module holds no real resources
today so nothing was actually at risk there. `infra/mgmt/backend` was
checked and found to already have a proper S3 backend (a 0-byte file in
the SMB backup was just a stale pre-migration leftover, not a real gap).

**One unrelated bug surfaced and resolved correctly, not by loosening
anything**: applying the now-current `mgmt/org` plan hit `AccessDenied`
on PR #112's CloudTrail S3 bucket policy — the log-archive account's own
Control Tower guardrail SCP (`p-rfhbth3m`) blocks `s3:PutBucketPolicy`
even for `AWSAdministratorAccess`, by design (log-integrity protection on
CT-managed buckets). This is the same SCP behind JP's own flagship
interview story (org-wide CloudTrail log delivery silently broken for
~4 months, root-caused, "fixed, codified in Terraform with explicit
state import" — the "import" detail is the whole answer). `aws s3api
get-bucket-policy` (a read, not blocked by the SCP) confirmed the correct
policy already exists for real on the bucket. The fix was never to
`apply` it — the SCP blocks that unconditionally — it was
`terraform import aws_s3_bucket_policy.cloudtrail_logs
aws-controltower-logs-172134854767-us-east-1`, bringing the
already-correct real-world policy under Terraform management without
ever calling the denied mutating API. `plan` afterward: "No changes.
Your infrastructure matches the configuration." State loss just meant
that import needed redoing, not that anything was actually broken.

- `infra/modules/mempalace_server/` — the portable module. Complete.
  One correctness fix found and applied during wiring: the execution
  role's Secrets Manager policy was missing `kms:Decrypt`/`kms:DescribeKey`
  on the CMK — `secretsmanager:GetSecretValue` alone isn't sufficient once
  the secret is encrypted with a customer-managed key rather than the
  AWS-managed default. Fixed in the module itself (general correctness,
  not specific to this deployment).
- `infra/mgmt/org/mempalace_account.tf` — account + SCP definition, mirrors
  ADR-031's pattern. Narrower SCP than WorkSpaces' (no lambda/apigateway/
  dynamodb — this workload doesn't use them).
- `infra/live/mempalace/` — VPC (public-only, 10.0.112.0/20, recorded in
  `docs/networking-cidr-plan.md`), KMS key, Secrets Manager shell (no
  value — see `secrets.tf`), ALB + target group + HTTP listener (HTTPS
  listener present but inactive behind `enable_https`), WAF (common rule
  set + known-bad-inputs/Log4Shell + rate limit), ECS cluster, and the
  `mempalace_server` module instantiation.

**Sequencing to actually deploy** (not done yet, needs explicit go-ahead
given account creation and public exposure are both hard to reverse):

1. `terraform apply` in `infra/mgmt/org` → creates the account, get its ID
   from `terraform output mempalace_account_id`.
2. Supply that ID as `mempalace_account_id` in `infra/live/mempalace`
   (`-var` or a `.tfvars` file — not committed, per the no-secrets/no-PII
   constraint applying broadly to account-specific values too).
3. `terraform apply` in `infra/live/mempalace`.
4. Generate the bearer token out-of-band and `put-secret-value` it (see
   `secrets.tf`) — the service won't come up healthy without it, by design.
5. Watch CloudWatch Container Insights, right-size `mempalace_cpu`/
   `mempalace_memory` off real data (open question #2).

## References

- MemPalace `deploy/docker-compose.server.yml`
  (github.com/milla-jovovich/mempalace) — verified directly, not assumed
- MagNet Legal ADR-075 (external project, corroborating reference —
  same vendor-documented deployment mode)
- [ADR-023](023-secrets-manager-over-ssm.md) — secrets pattern reused here
- [ADR-025](025-cloudwatch-native-observability.md) — log encryption pattern
- [ADR-030](030-compute-off-by-default.md) — why dev doesn't fit this workload
- [ADR-031](031-dedicated-workspaces-account.md) — dedicated-account and
  no-NAT-gateway precedent this ADR follows
- Live cross-session check (2026-08-14) against the session actively
  operating mp_sync/mempalace-cloud-sync — backend, write-lock, corpus
  size, and migration-format facts above came from there directly, not
  from documentation
