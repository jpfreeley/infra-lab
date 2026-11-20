# Deploying the NetBird Stack into Another AWS Environment

How to stand up the same server, monitor, and up/down automation in an AWS
account outside infra-lab, for example a company's own account. The
infra-lab deployment is the reference; this page lists every value tied to
it and the order that works.

The GitHub half (workflows, OIDC role, repo variables, token) is in
[github-setup.md](github-setup.md). Do both.

Expect about half a day for the first deployment, most of it waiting on
certificates, the first cold start, and enrolling tablets.

## 0. Decisions to make first

| Decision | infra-lab choice | Notes |
| --- | --- | --- |
| Account layout | dedicated account in an AWS Organization, with an SCP | A single standalone account works. Keep the server out of an account other teams deploy into: whoever controls it can add peers that reach every tablet. |
| Domain | `netbird.lintwiselabs.com` | Needs a public Route53 hosted zone you control, for ACM DNS validation and the alias record. |
| Region | `us-east-1` | Any region with Fargate, NLB and EFS. |
| Check-in times | 06:00, 12:00, 18:00, 00:00 America/New_York | Any list of local times plus an IANA zone. |
| STUN | Cloudflare and Google public STUN | Embedded STUN through the NLB got no replies in the spike (ADR-037). Keep the public STUN default. |
| TLS | `nlb` (ACM certificate on the NLB) | Proven in the spike. `traefik` (Let's Encrypt) is the fallback. |
| ADB key for the monitor | the operator's existing key | Or generate a new key pair for the monitor and authorize it on each tablet once. |

Moving existing tablets to a new server means re-enrolling them (new
server URL in the NetBird app, new login, new NetBird IPs). Peers do not
move between servers.

## 1. Tools and access

- Terraform 1.7 or later, AWS CLI v2, `jq`, `gh`, Python 3.9+, `htpasswd`
  (ships with macOS).
- Admin credentials in the target account (and in the account that holds
  the Route53 zone, if different).
- Session Manager plugin for the AWS CLI (`aws ssm start-session`), for
  shell access to the monitor.

## 2. Copy the code

Into the target repo, keeping the same relative layout:

| From infra-lab | Why |
| --- | --- |
| `infra/modules/netbird_server` | the server (ECS task, EFS, IAM) |
| `infra/modules/tablet_monitor` | the monitor (EC2, S3 code bucket, IAM) |
| `infra/modules/{vpc,ecs_cluster,kms_key,secrets_manager,security_group,s3_secure_bucket}` | used by the two modules and the live stack |
| `infra/live/netbird` | the live wiring (rename the folder if you like) |
| `.github/workflows/netbird-toggle.yml`, `netbird-lease-teardown.yml` | up/down and lease logic |
| `infra/live/dev/lambda/idle_teardown_trigger/handler.py` and `infra/live/dev/netbird_lease_teardown_trigger.tf` | the 15-minute clock (optional but recommended) |
| `scripts/netbird/` | operator scripts |

Delete `infra/live/netbird/.terraform` and any `*.tfstate` if you copied a
working directory instead of a clean checkout.

## 3. State backend

The live stack uses an S3 backend with DynamoDB locking. Create a bucket
(versioned, encrypted, public access blocked) and a DynamoDB table with a
`LockID` string partition key, or reuse the ones you have. Then edit the
`backend "s3"` block in `providers.tf`: `bucket`, `key`, `region`,
`dynamodb_table`.

## 4. Change the environment values

| File | Value | Change to |
| --- | --- | --- |
| `providers.tf` | backend `bucket`, `dynamodb_table` | your backend (step 3) |
| `providers.tf` | default provider `assume_role` into `OrganizationAccountAccessRole` | your deploy role in the target account, or remove the block if your credentials are already in that account |
| `providers.tf` | `aws.dns` provider | credentials for the account that holds the hosted zone (same account: copy the default provider's settings) |
| `providers.tf` | `default_tags` (`Project`, `Owner`) | your tags |
| `variables.tf` | `netbird_account_id` | target account ID |
| `variables.tf` | `domain` | your server name, for example `netbird.example.com` |
| `variables.tf` | `aws_profile` | your local profile name |
| `variables.tf` | `monitor_checkins` | your check-in times (keep equal to the `NETBIRD_CHECKINS` repo variable) |
| `locals.tf` | `project` | your project name. It prefixes every resource and secret name (`<project>-<environment>/...`) |
| `locals.tf` | `vpc_cidr`, `public_subnets` (CIDRs and AZs) | a free /20 in your address plan, two AZs in your region |
| `acm.tf` | `data "aws_route53_zone"` name (`lintwiselabs.com.`) | your zone, with the trailing dot. Rename the data source if you like |
| `.github/workflows/*` | account IDs, role names, the readiness URL, the monitor's `Name` tag | see [github-setup.md](github-setup.md) step 4 |
| `scripts/netbird/netbird.sh` | `NETBIRD_REPO`, `NETBIRD_HOST` defaults | your repo and server name (or set them as environment variables) |

If the target account is in an AWS Organization with service control
policies, allow at least: `ecs`, `ec2`, `elasticfilesystem`,
`elasticloadbalancing`, `kms`, `secretsmanager`, `iam`, `sts`, `logs`,
`cloudwatch`, `s3`, `ssm`, `ssmmessages`, `ec2messages`, `acm`, and
`route53` if the zone is in the same account. infra-lab's version is
`infra/mgmt/org/netbird_account.tf`.

## 5. Phase 1: KMS key and secret shells

```bash
cd infra/live/netbird
terraform init
terraform plan -out=tfplan \
  -target=module.netbird_kms \
  -target=module.netbird_auth_secret -target=module.netbird_store_key \
  -target=module.netbird_cookie_key -target=module.netbird_owner \
  -target=module.monitor_setup_key -target=module.monitor_adb_key \
  -target=module.monitor_ntfy_topic -target=module.monitor_inventory
terraform apply tfplan && rm tfplan
```

Read the plan before applying: only the KMS key and eight secrets (plus
their policies) should be created.

## 6. Fill the server secrets

Commands are in `infra/live/netbird/secrets.tf` and in
`infra/modules/netbird_server/README.md`. Replace the `infra-lab-netbird`
prefix with your `<project>-<environment>`. In short:

- `.../netbird/auth-secret`: `openssl rand -base64 32 | tr -d '=\n'`
- `.../netbird/store-encryption-key`: `openssl rand -base64 32 | tr -d '\n'`.
  **Losing this value makes the server's database unreadable.** Never
  delete or rotate it.
- `.../netbird/session-cookie-key`: `openssl rand -base64 32 | tr -d '\n'`
- `.../netbird/owner`: JSON `{email, password, password_hash}` with a
  **bcrypt** hash, from the Python snippet in the module README. A
  plaintext password in `password_hash` makes every login fail with HTTP
  500.

Always pipe values into `--secret-string file:///dev/stdin`, so they never
appear on a command line or in shell history.

## 7. Phase 2: the server

```bash
terraform plan -out=tfplan \
  -target=module.netbird -target=module.netbird_cluster \
  -target=aws_lb.netbird -target=aws_lb_listener.https \
  -target=aws_lb_target_group.https \
  -target=aws_acm_certificate_validation.netbird \
  -target=aws_route53_record.netbird
terraform apply tfplan && rm tfplan
```

This pulls in the VPC, security groups and certificate as dependencies.
The first apply waits for ACM validation (a few minutes). Then wait for
readiness:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  https://<domain>/oauth2/.well-known/openid-configuration
```

200 means ready. A cold start took 2.5 to 6.5 minutes in the spike. If it
stays down, read the ECS service events and the task's CloudWatch log
group (`terraform output log_group_name`).

## 8. Configure NetBird in the dashboard

Open `https://<domain>` and log in as the owner (email and password from
the owner secret).

1. **Access Control > Policies**: delete the **Default** (all to all)
   policy.
2. **Access Control > Groups**: create `admin-macs`, `admin-tablets`,
   `monitors`.
3. **Policies**, all with Bidirectional off:
   - `Mac2Tablet`: source `admin-macs`, destination `admin-tablets`, all
     protocols and ports.
   - `Monitor2Tablet`: source `monitors`, destination `admin-tablets`,
     TCP, all ports.
   - `Mac2Monitor`: source `admin-macs`, destination `monitors`, TCP 8080.
4. **Settings > Groups**: **Enable user group propagation** on.
5. **Users**: give the owner account no auto-assigned groups. Invite the
   operators with auto-group `admin-macs` ([adding-people.md](adding-people.md)).
6. **Setup Keys > Create Setup Key** for the monitor: one-off (single use),
   not ephemeral, auto-assigned group `monitors`, expiry 30 days or more.
   Copy it.

Enroll your own Mac now (adding-people.md, Part B) and check that
`netbird status` shows Management connected.

## 9. Fill the monitor secrets

Commands are in `infra/live/netbird/monitor_secrets.tf`:

- `.../tablet-monitor/setup-key`: the key from step 8. Check before
  storing: it is a 36-character UUID (`8-4-4-4-12` hex). A wrong or
  already-used key shows as `setup key is invalid` in
  `/var/log/netbird/client.log` on the monitor, and the monitor never joins.
- `.../tablet-monitor/adb-key`: JSON `{private, public}` of an ADB key pair
  that the tablets trust. To give the monitor its own key instead, run
  `adb keygen monitor-adbkey` on any machine, store that pair, and
  authorize it on each tablet once (tablet-setup.md, step 8).
- `.../tablet-monitor/ntfy-topic`: `printf 'tablets-%s' "$(openssl rand -hex 16)"`.
  Subscribe to that topic in the ntfy app on every operator's phone. Treat
  the name as a secret: anyone who knows it can read the alerts.
- `.../tablet-monitor/inventory`: `{"tablets": []}` for now. Tablets are
  added as they are set up (tablet-setup.md, step 7).

## 10. Phase 3: everything else

```bash
terraform plan -out=tfplan
terraform apply tfplan && rm tfplan
```

This creates the monitor (EC2 instance, its S3 code bucket, IAM role,
instance profile) and anything left over. Check the plan: no destroys.

Verify the monitor:

```bash
ID=$(terraform output -raw tablet_monitor_instance_id)
aws ssm start-session --target "$ID"
# on the instance:
sudo cat /var/log/tablet-monitor-bootstrap.log   # ends with "bootstrap done"
sudo netbird status                              # Management: Connected
sudo journalctl -u tablet-monitor -n 50
```

In the dashboard, the monitor appears as peer `tablet-monitor` in group
`monitors`. Its page is at `http://<monitor-netbird-ip>:8080/` from a Mac
in `admin-macs`.

## 11. Hand over to the automation

1. Do [github-setup.md](github-setup.md).
2. Set a lease and test the loop:

   ```bash
   NETBIRD_REPO=<owner>/<repo> NETBIRD_HOST=<domain> scripts/netbird/netbird.sh up 30m
   ```

   After 30 minutes plus one 15-minute check, the lease workflow tears the
   server down and stops the monitor. The ntfy topic gets "Tablet monitor
   down" when it stops and "Tablet monitor up" when it next starts.
3. Set up tablets ([tablet-setup.md](tablet-setup.md)).

## 12. Cost

us-east-1 on-demand, with four check-ins of about an hour each per day:

| Item | Monthly |
| --- | --- |
| NetBird server (NLB + Fargate 0.5 vCPU / 2 GB), about $30 if always on | about $5 |
| Monitor t3.nano, public IPv4 and 8 GiB disk | about $2 |
| KMS key | $1 |
| Secrets Manager, 8 secrets | about $3.20 |
| EFS, a few MB | cents |
| **Total** | **about $11** |

Plus any account-wide security services your organization enables
(GuardDuty, Config, Security Hub), usually $1 to $3 a month for an account
this small. Each extra hour of lease costs about $0.06.

## What not to do

- Never destroy EFS, the KMS key or the store-encryption-key secret. They
  hold every peer's identity. The toggle workflow never touches them.
- Never run two server tasks against the same EFS (SQLite). The module caps
  the service at one task.
- Never put secret values in `.tfvars`, variable defaults, or the repo.
- Changing the monitor's bootstrap (template, pinned versions, instance
  settings) replaces the instance, which enrolls as a new peer: delete the
  old `tablet-monitor` peer in the dashboard and store a new one-use setup
  key first. Changing only `monitor.py` does not replace anything.
