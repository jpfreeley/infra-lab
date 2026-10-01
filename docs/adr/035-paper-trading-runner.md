# ADR-035: Scheduled Paper Trading Runner

## Status

Accepted. Deployed to the dev account and verified against a live Alpaca paper
account on 2026-09-25.

## Context

JP wants a model-driven agent that trades an Alpaca **paper** account on a
schedule, unattended, with hard safety limits, phone notifications, and the
ability to run more than one independent strategy side by side. It must cost
close to nothing when idle, must not depend on a laptop being awake, and must
keep everything strategy-specific out of this public repository.

## Decision

A single Lambda, invoked by EventBridge Scheduler, runs one wakeup of the agent
per invocation. The agent calls Claude through Amazon Bedrock with a fixed set
of tools that wrap the Alpaca REST API.

- **Scheduler, not GitHub cron.** EventBridge Scheduler has a real SLA and a
  timezone-aware cron, so daylight saving is handled. GitHub's scheduled
  workflows proved unreliable in ADR-034.
- **Lambda, not a CLI in a container.** Each wakeup is short and stateless. A
  small Python runner with a tool loop over Bedrock Converse avoids packaging an
  agent CLI and keeps every write behind our own code.
- **Limits live in code.** Every write path goes through a guarded tool layer:
  paper-account check, per-order and daily limits, bracket orders only, size and
  target computed by code, deterministic client order ids, a write-ahead
  journal, a run lock and per-run cost and turn caps. The model supplies
  judgment; it cannot exceed a limit.
- **Fail closed.** Limits are loaded from private config at runtime with no
  defaults. Missing or out-of-bounds values stop the run and alert.
- **Strategy is data, not code.** Strategy text, prompts, numeric limits, the
  symbol universe and schedule times are private config in an S3 prefix and a
  gitignored tfvars file. None of it is committed here.
- **Inert by default and self-expiring.** The runner does nothing unless a
  control object exists in the state bucket and today is inside its date window.
- **Multiple strategies.** An optional strategy id in the invocation payload
  keys config, state, credentials, the control object and notification labels.
  The default strategy keeps the original layout. Extra ids and their schedules
  come from tfvars, and each gets its own empty credentials secret and its own
  Alpaca paper account.
- **Secrets.** Created empty and populated out-of-band (ADR-023), matching the
  `secret_string = null` pattern used elsewhere.
- **Notifications** go through ntfy.sh with an unguessable topic held in a
  secret.
- **Deployment account.** The dev/management account, beside the mempalace
  Lambdas, because the mempalace account's SCP denies Lambda and EventBridge.

## Operation

`scripts/alpaca_trading.sh [--strategy ID]` stores secrets with hidden prompts,
syncs private config, enables or disables a window, prints status, journals and
handoff records, and invokes a slot (with an optional dry run that simulates
every write against isolated state). It always targets the infra-lab account,
ignores any ambient AWS profile in the caller's shell, and verifies the account
id before acting.

## Consequences

- Idle cost is a few dollars a month (secrets and one KMS key). Variable cost is
  almost entirely model tokens, capped per run.
- Adding a same-shaped strategy is configuration plus a targeted apply. Changing
  the shape of trading (instruments, overnight holds, exit styles, cadence)
  needs code changes to the guardrail layer.
- `live/dev` state currently tracks only the mempalace and trading resources.
  A plain `terraform apply` would try to create the rest of the dev environment,
  so these resources are applied with `-target`.
- Paper fills are more forgiving than live fills, and a two-week run is far too
  short to prove an edge. Results measure the system first and the strategy
  second.
- The runner is intentionally paper-only. Pointing it at a live account would
  need a deliberate design change to the account check and the guardrails.
