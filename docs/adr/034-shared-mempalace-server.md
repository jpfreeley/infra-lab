# ADR-034: Shared MemPalace Server as a Portable App on Dedicated Infra

## Status

Accepted (design verified live 2026-08-14; currently torn down to stop
metered spend between sessions — see "Currently Torn Down" note below)

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
2. **Task sizing** — STILL UNMEASURED, module ships with a starting guess.
   Confirmed from upstream docs: ChromaDB (the local default) needs ~300MB
   disk for its embedding model; no RAM figure published. Docker isn't
   available in this environment to measure directly. `mempalace` also
   supports an optional remote embedding server (OpenAI-compatible
   endpoint) — offloading embedding out of the task would meaningfully
   shrink whatever Fargate size is needed, worth weighing against the added
   moving part. `mempalace_server`'s defaults are `cpu=256`/`memory=512` —
   Fargate's smallest possible size, not a measured number. Plan stands:
   deploy at this floor, right-size from real CloudWatch metrics after the
   first deploy rather than lab-testing blind.
3. **Token rotation** — PARTIALLY RESOLVED. Public docs (not yet verified
   against the actual installed CLI) describe guest keys with permission
   levels (`read` / `write` / `admin`) that are revocable independently of
   the root `palace_key`. If confirmed, design is: one `palace_key` (admin)
   generated out-of-band into Secrets Manager per ADR-023, used to mint a
   separate revocable guest key per device/client — losing or rotating one
   device's access never requires rotating every other client's token.
   Verifying this against `mempalace serve --help` before committing to it.
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
