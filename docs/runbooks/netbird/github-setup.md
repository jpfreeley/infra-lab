# GitHub Setup for the NetBird Stack

What GitHub has to provide so that the server and the monitor come up for
check-ins and leases, and go down again on their own. Do this after (or
alongside) [deploy-new-aws.md](deploy-new-aws.md).

## What lives on GitHub

| Piece | Role |
| --- | --- |
| `netbird-toggle.yml` | `up`: targeted `terraform apply` of the NLB, listener, target group, DNS record and ECS service, waits for readiness, starts the monitor. `down`: stops the monitor, targeted `terraform destroy` of the same resources. |
| `netbird-lease-teardown.yml` | every 15 minutes: decides "wanted up" (lease active or check-in window open), compares with reality, calls the toggle, and starts or stops the monitor to match. |
| Repo variables | `NETBIRD_KEEP_UP_FROM`, `NETBIRD_KEEP_UP_UNTIL` (the lease), `NETBIRD_CHECKINS` (check-in times). |
| OIDC trust | lets the workflows assume an AWS role without stored AWS keys. |
| Fine-grained token (in AWS) | lets the EventBridge clock dispatch the lease workflow. |

## 1. Repository

- The workflows must be on the **default branch**. `schedule` and
  `workflow_dispatch` only run workflow files from there.
- Settings > Actions > General: Actions allowed. The workflows declare
  their own `permissions` (`id-token: write`, `contents: read`), so the
  default token permission can stay read-only.
- Protect the default branch (require a pull request). Everyone who can
  start the server needs write access (step 6), and write access also
  allows pushing workflow changes; branch protection keeps those reviewed.
- **Public repos:** GitHub disables scheduled workflows after 60 days with
  no repository activity. A disabled workflow cannot be dispatched by the
  EventBridge clock either. Check with `gh workflow list --all` and
  re-enable with `gh workflow enable netbird-lease-teardown.yml`.

## 2. AWS OIDC provider and deploy role

In the AWS account where the workflows start (infra-lab: the management
account; a single-account setup: the NetBird account itself):

1. IAM > Identity providers > add OpenID Connect provider:
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
2. A role the workflows assume, with this trust condition:

   ```json
   "Condition": {
     "StringEquals": {
       "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
     },
     "StringLike": {
       "token.actions.githubusercontent.com:sub": "repo:<owner>/<repo>:ref:refs/heads/main"
     }
   }
   ```

   Use your default branch name. **Repositories created after 2026-07-15**
   (or opted in) get an immutable `sub` claim that includes numeric IDs,
   for example `repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:refs/heads/main`.
   Match whichever form your repo sends; a mismatch fails with
   "Not authorized to perform sts:AssumeRoleWithWebIdentity".
3. Permissions: enough to run `terraform apply` and `destroy` on the
   NetBird stack (ECS, ELB, Route53 records, EC2 start/stop, plus read
   access to everything else in the stack) and to the Terraform state
   bucket and lock table. infra-lab's role
   (`infra/mgmt/org/github_oidc.tf`) uses AdministratorAccess scoped by
   the trust policy; a new deployment should consider a narrower policy.
4. If the NetBird resources are in a different account from the role
   (infra-lab's layout), the role must be able to assume a role there
   (`OrganizationAccountAccessRole` in infra-lab).

## 3. Repo variables

```bash
REPO=<owner>/<repo>
gh variable set NETBIRD_CHECKINS --repo $REPO --body "06:00,12:00,18:00,00:00 America/New_York"
gh variable set NETBIRD_KEEP_UP_FROM --repo $REPO --body ""
gh variable set NETBIRD_KEEP_UP_UNTIL --repo $REPO --body "2000-01-01T00:00:00Z"
```

- `NETBIRD_CHECKINS`: comma-separated local times, a space, an IANA time
  zone. Daylight saving time is handled. Empty means no check-ins. Keep it
  equal to `monitor_checkins` in `infra/live/netbird/variables.tf`, which
  the monitor uses for its own schedule.
- `NETBIRD_KEEP_UP_FROM` / `UNTIL`: ISO 8601 UTC timestamps. `netbird.sh up`
  and `down` write them; you do not normally set them by hand.

## 4. Edit the workflows for your environment

| File | Line | Change |
| --- | --- | --- |
| `netbird-toggle.yml` | `role-to-assume: arn:aws:iam::551452024305:role/infra-lab-github-actions-deploy` | your deploy role ARN (step 2) |
| `netbird-toggle.yml` | `URL="https://netbird.lintwiselabs.com/oauth2/..."` | your domain |
| `netbird-toggle.yml` | two `--role-arn arn:aws:iam::300077301490:role/OrganizationAccountAccessRole` (monitor start and stop) | your NetBird account role. Single account: delete the `assume-role` lines and the `export` of the temporary keys; the job credentials already work. |
| `netbird-toggle.yml` | `Name=tag:Name,Values=infra-lab-netbird-tablet-monitor` | `<project>-<environment>-tablet-monitor` |
| `netbird-toggle.yml` | `working-directory: infra/live/netbird`, `terraform_version` | your path and version |
| `netbird-lease-teardown.yml` | the same two role ARNs and the monitor `Name` tag | same as above |
| `netbird-lease-teardown.yml` | `--names infra-lab-netbird-nlb` (how it detects "up") | `<project>-<environment>-nlb` |
| `netbird-lease-teardown.yml` | `cron: "7,22,37,52 * * * *"` | keep (fallback clock) |

After editing, search both files for any remaining `551452024305`,
`300077301490`, `lintwiselabs` and `infra-lab`:

```bash
grep -nE '551452024305|300077301490|lintwiselabs|infra-lab' .github/workflows/netbird-*.yml
```

## 5. The 15-minute clock (EventBridge, primary)

GitHub's own `schedule` trigger is best effort; gaps of hours have been
measured (ADR-034). So an EventBridge Scheduler rule calls a small Lambda
every 15 minutes, and the Lambda dispatches the lease workflow through the
GitHub API. The cron in the workflow stays as the fallback.

1. Create a **fine-grained personal access token** (GitHub > Settings >
   Developer settings > Fine-grained tokens):
   - Resource owner: the repo's owner. Repository access: only this repo.
   - Repository permissions: **Actions: Read and write**. Nothing else.
   - Expiration: the longest your policy allows. Put a reminder in a
     calendar for the renewal; an expired token is the most likely silent
     failure (teardowns then arrive late through the fallback cron).
2. Store it in Secrets Manager in the account that runs the Lambda, never
   in the repo:

   ```bash
   pbpaste | tr -d '\n' | aws secretsmanager put-secret-value \
     --secret-id <trigger-token-secret> --secret-string file:///dev/stdin
   ```

3. Deploy the trigger: `infra/live/dev/netbird_lease_teardown_trigger.tf`
   (Lambda, its role, the schedule) with `handler.py`. Set
   `GITHUB_REPO = "<owner>/<repo>"`, `WORKFLOW_FILE =
   "netbird-lease-teardown.yml"` and the token secret ARN. Lambda and
   EventBridge must be allowed in that account (infra-lab runs them in the
   management account because the NetBird account's SCP denies them).
4. Check: Lambda > Monitor > logs show a dispatch every 15 minutes, and
   `gh run list --workflow netbird-lease-teardown.yml` shows
   `workflow_dispatch` runs at that rhythm.

## 6. Who can start the server

`netbird.sh up`, `down` and `checkin` (when the monitor is down) set repo
variables and dispatch the toggle. Both need **write** access to the repo:

- Repository variables: collaborator access on a personal-account repo,
  write access on an organization repo.
- Dispatching a workflow: write access (classic tokens need `repo` scope).

On a **personal-account repo**, collaborators always get write access to
the whole repo; there is no narrower role. On an **organization repo** you
can give operators the Write role on just this repo. If the repo also
holds unrelated infrastructure, consider a small separate repo for the
NetBird workflows and live stack, so operator access stops there.

Operators run `gh auth login` once. On a machine with several `gh`
accounts, set `NETBIRD_GH_USER=<github-user>` so the script switches to the
right one.

## 7. Verify end to end

```bash
scripts/netbird/netbird.sh status   # DOWN, no lease, window open/closed
scripts/netbird/netbird.sh up 30m   # READY after a few minutes
scripts/netbird/netbird.sh checkin  # prints every tablet's result
scripts/netbird/netbird.sh down     # teardown triggered
```

Then wait for the next check-in window and confirm, without touching
anything, that `gh run list --workflow netbird-toggle.yml` shows an `up`
25 to 40 minutes before the check-in time and a `down` 15 to 30 minutes
after it (the lease check runs every 15 minutes), and that the ntfy topic got "Tablet monitor up" and "Tablet
monitor down".
