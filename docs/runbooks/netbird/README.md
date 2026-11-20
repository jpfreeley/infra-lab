# NetBird Tablet Remote Access: Runbooks

Remote control of Android kiosk tablets (screen and ADB) over a private,
self-hosted NetBird network, with a monitor that checks every tablet four
times a day. Design and reasoning: [ADR-037](../../adr/037-netbird-server-dedicated-account.md)
(server) and [ADR-038](../../adr/038-netbird-tablet-monitor.md) (monitor).

## Start here

| I want to... | Read |
| --- | --- |
| Set up a new tablet | [tablet-setup.md](tablet-setup.md) |
| Give a person access (their Mac on the network) | [adding-people.md](adding-people.md) |
| Run the whole stack in a different AWS account | [deploy-new-aws.md](deploy-new-aws.md) |
| Set up the GitHub side (workflows, OIDC, variables, token) | [github-setup.md](github-setup.md) |
| Understand the status page, alerts and check-ins | [monitoring.md](monitoring.md) |
| Day-to-day use, troubleshooting, known gaps | [operations.md](operations.md) |

## How it fits together

```text
                      internet
                          |
   GitHub Actions --------+-------- netbird.lintwiselabs.com (NLB, TLS 443)
   (lease workflow,       |              |
    toggle workflow)      |         ECS Fargate task: NetBird server
          |               |         (management, signal, relay, dashboard)
          | starts/stops  |              |  state on EFS
          v               |
   tablet monitor (EC2) --+---- WireGuard overlay (NetBird) ----+
          |                                                     |
          | ADB over the overlay                                |
          v                                                     v
   tablets (Android, NetBird app,                operators' Macs (NetBird app,
   Automate flow, kiosk app)                     adb, scrcpy, status page)
```

- **The NetBird server** is the control plane. It tells peers how to find
  each other. It does not carry the screen traffic, except when two peers
  cannot connect directly and fall back to its relay.
- **The server is torn down to zero most of the day.** It comes up for four
  daily check-ins (06:00, 12:00, 18:00, 00:00 New York time, about an hour
  each) and whenever someone takes a lease (`netbird.sh up 2h`).
  Connections that are already open keep working after a teardown, but a
  tablet that reboots cannot rejoin until the server is back.
- **The tablet monitor** is a small EC2 instance on the overlay. It runs
  only while the server is up, checks each tablet over ADB, serves a status
  page on its overlay address, and sends a push message (ntfy) when a tablet
  is red.
- **Each tablet** runs the NetBird app (always-on VPN), the kiosk app, and an
  Automate flow that restarts the kiosk app after a reboot, brings it back
  to the front, keeps Wireless debugging on, and writes an event log.

## Access model

| Group (NetBird) | Members | Can reach |
| --- | --- | --- |
| `admin-macs` | operators' computers | tablets (all ports), monitor page (TCP 8080) |
| `monitors` | the tablet monitor | tablets (all ports) |
| `admin-tablets` | tablets | nothing (targets only, never sources) |

Policies: `Mac2Tablet` (`admin-macs` to `admin-tablets`), `Monitor2Tablet`
(`monitors` to `admin-tablets`), `Mac2Monitor` (`admin-macs` to `monitors`,
TCP 8080). All one way. The default all-to-all policy is deleted.

## Scripts

All in [`scripts/netbird/`](../../../scripts/netbird/):

| Script | Runs on | Does |
| --- | --- | --- |
| `netbird.sh` | operator's Mac | `status`, `up [duration]`, `down`, `checkin` for the server and monitor |
| `tablet-adb.sh` | operator's Mac | connect ADB to a tablet (recovers port 5555 after a reboot), optional `scrcpy` |
| `tablet-setup.sh` | operator's Mac | `check` or `apply` the ADB-side settings on a tablet |

## Where things live

| Thing | Location |
| --- | --- |
| Server module | `infra/modules/netbird_server` |
| Monitor module | `infra/modules/tablet_monitor` (code: `files/monitor.py`) |
| Live stack | `infra/live/netbird` |
| AWS account and SCP | `infra/mgmt/org/netbird_account.tf` |
| Lease clock (EventBridge + Lambda) | `infra/live/dev/netbird_lease_teardown_trigger.tf` |
| Workflows | `.github/workflows/netbird-toggle.yml`, `netbird-lease-teardown.yml` |
| Secrets (values) | AWS Secrets Manager in the NetBird account, never in the repo |
| Tablet inventory | Secrets Manager, `infra-lab-netbird/tablet-monitor/inventory` |
