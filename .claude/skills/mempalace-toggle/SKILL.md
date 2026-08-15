---
name: mempalace-toggle
description: Bring the shared MemPalace server (mempalace.lintwiselabs.com) up or down via its GitHub Actions workflow. Use this whenever the user asks to start, stop, spin up, spin down, turn on, turn off, or check the status of "mempalace" the server/deployment (not the mempalace MCP memory tool itself), mentions the mempalace domain being unreachable, or wants to save money by tearing the mempalace deployment down between uses. Triggers on phrases like "bring mempalace up", "turn off mempalace", "spin down the memory server", "is the mempalace server running", "/mempalace up", or "kill the mempalace ALB to save money".
---

# MemPalace Server Toggle

Controls the billable AWS resources behind `https://mempalace.lintwiselabs.com`
(a hosted MemPalace Remote/Team Server) via a GitHub Actions workflow in the
`infra-lab` repo — `up` creates them, `down` destroys them. Everything else
behind this deployment (VPC, EFS, KMS key, Secrets Manager secret, ECS
cluster, IAM roles, task definition) stays up permanently and costs close to
nothing either way, so toggling never touches data or requires regenerating
the bearer token.

Full design and deployment history: `docs/adr/034-shared-mempalace-server.md`
in the infra-lab repo, if you need more context than this skill covers.

## Why this exists

The ALB + WAF + ECS Fargate task together cost roughly $35-40/mo while
running, versus about $1.40/mo (just the KMS key + secret) while torn down.
Since this is a personal-use deployment, it's worth actually turning off
when nobody's using it rather than paying the always-on rate — that's the
whole point of the workflow this skill drives.

## Running it

1. **Trigger the workflow.** From the `infra-lab` repo (the `gh` CLI needs
   to be run from inside it, or use `--repo jpfreeley/infra-lab`):

   ```bash
   gh workflow run mempalace-toggle.yml -f action=up    # or: action=down
   ```

2. **Find the run you just triggered.** `workflow_dispatch` doesn't return a
   run ID directly, so grab the most recent run for this workflow right
   after triggering it:

   ```bash
   gh run list --workflow=mempalace-toggle.yml --limit 1
   ```

3. **Watch it to completion** — don't just report "triggered," the whole
   value here is knowing whether it actually worked:

   ```bash
   gh run watch <run-id> --exit-status
   ```

   A non-zero exit means it failed — check `gh run view <run-id> --log-failed`
   and report the real error rather than guessing at it.

   **`up` can genuinely take a while — don't assume it's stuck.** Most runs
   finish in 3-4 minutes, but the WAF-to-ALB association
   (`aws_wafv2_web_acl_association`) has been observed taking as long as
   9-10 minutes on the AWS side in an otherwise completely normal run (total
   12m44s that time, confirmed by checking the AWS resources directly mid-run
   — the ALB, ECS service, and WAF were all already correctly created and
   healthy while Terraform was still waiting on this one association to
   report back). This looks like AWS-side API variability for that specific
   call, not anything wrong with the deployment. `gh run watch` already
   handles this correctly by just waiting — the only wrong move here is
   assuming it's hung and interrupting it before ~10-15 minutes have passed.
   If you want to sanity-check progress without waiting for the whole watch
   to finish, `aws elbv2 describe-load-balancers` / `aws ecs describe-services`
   / `aws wafv2 list-web-acls` (profile `infra-lab-mempalace`, region
   `us-east-1`) will show you what's actually landed in AWS already, which is
   often ahead of what the workflow log has printed.

## After `up` succeeds: verify it's actually healthy, not just applied

This is the one non-obvious part, worth getting right: the GitHub Actions
job finishing green only means `terraform apply` succeeded — it does **not**
mean the ECS task is done starting. The task needs to pull its container
images and pass a health check grace period (roughly 90 seconds) after the
Terraform apply itself completes before it's actually reachable. Reporting
"it's up!" the moment the workflow shows green, without checking, is the
kind of claim that's technically-based-on-something but not actually true
yet.

So after the workflow succeeds on `up`, confirm the real thing:

```bash
curl -sk -o /dev/null -w "%{http_code}\n" --max-time 15 https://mempalace.lintwiselabs.com/healthz
```

If it's not `200` yet, that's expected right after a fresh `up` — wait
somewhere in the 30-90 second range and check again rather than declaring
failure immediately. Once it returns `200`, that's the real "it's live"
signal, and worth telling the user the URL at that point:
`https://mempalace.lintwiselabs.com`.

## After `down` succeeds

No health check needed — a `down` that reports success genuinely means the
billable resources are gone (confirmed by direct testing when this workflow
was built: `aws ecs list-tasks` / `elbv2 describe-load-balancers` /
`wafv2 list-web-acls` all come back empty). Just report the cost is back
down to the ~$1.40/mo baseline.

## Things worth knowing, not worth re-discovering

- **Idempotent either direction.** Running `up` when it's already up, or
  `down` when it's already down, is safe — Terraform just reports no
  changes needed for whichever resources already match the desired state.
- **The domain's DNS record survives teardown correctly.** Destroying the
  ALB automatically pulls the Route53 alias record for
  `mempalace.lintwiselabs.com` into the same destroy (Terraform won't leave
  it pointing at a resource that's gone), and it comes back correctly
  pointed at the new ALB on the next `up` — no manual DNS fixing needed
  either direction.
- **The bearer token never needs regenerating from a toggle.** It lives in
  Secrets Manager, which isn't touched by either `up` or `down`.
- If `gh workflow run` fails with something like "workflow not found," you're
  probably not in the `infra-lab` repo — either `cd` into it or add
  `--repo jpfreeley/infra-lab` to every `gh` command above.
