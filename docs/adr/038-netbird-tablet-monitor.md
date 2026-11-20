# ADR-038: Always-On Tablet Monitor on NetBird, Business-Hours Uptime

## Status

Proposed. Builds on ADR-037 (self-hosted NetBird server). Nothing is
applied yet.

## Context

ADR-037 put kiosk tablets (Android, unrooted) on a self-hosted NetBird
network so they can be driven with ADB and `scrcpy`. The spike and the
follow-up work on 2026-11-19 and 2026-11-20 made each tablet recover on its
own after a reboot: an on-device Automate flow keeps Wireless debugging on
and starts the kiosk app once per boot, and a script on the operator's Mac
(`tablet-adb.sh`) finds the Wireless debugging port and switches ADB back to
TCP 5555. A second script (`tablet-setup.sh check`) reports a tablet's
configuration over ADB.

What is missing is continuous visibility. Today nobody knows a tablet is
broken until someone at the site notices. The operator wants:

- A small status page ("network map") that shows every tablet and refreshes
  on its own.
- A push notification (ntfy) when a tablet goes red.
- Red to cover eight conditions: the tablet is offline on NetBird, ADB is
  unreachable, the kiosk app is not running, the kiosk app is not in the
  foreground, the tablet's printer is not available, the tablet's Google
  account is signed out, the kiosk app has lost its backend connection, or
  the app's "Live" status label is gone.
- The page to also show the app's active order count and the last order
  seen, for information.
- A way to reboot a tablet remotely.
- The checks to run without the operator's Mac (it sleeps, travels, and is
  off at night).
- Coverage during business hours only: 10:00 to 23:00 America/New_York,
  every day.

### Constraints from ADR-037

- **The server is torn down when its lease ends.** Established WireGuard
  tunnels survive a teardown, but a tablet that reboots cannot rejoin until
  the server is back (it needs management and signal to learn peer
  endpoints). Any monitor is only meaningful while the server is up, so
  monitoring hours and server hours must be the same window.
- **Cold start is not instant.** A server bring-up took 6.5 minutes in the
  spike, and NetBird clients back off while the server is away: one tablet
  rejoined about 8 minutes after the server was ready.
- **The NetBird account's SCP** (`infra/mgmt/org/netbird_account.tf`)
  denies everything outside an allow list. EC2 and S3 are on it; Lambda and
  EventBridge are not, by design.

### Why the monitor cannot be serverless

The monitor has to be a NetBird peer, because ADB is only reachable inside
the overlay. The NetBird client needs a TUN device (or `NET_ADMIN` to create
one). Fargate grants neither: its only addable Linux capability is
`SYS_PTRACE`. NetBird has a userspace "netstack" mode that needs no TUN, but
it exposes peers only through a SOCKS5 proxy, and the `adb` client has no
proxy support. Lambda is denied by the SCP and has the same TUN problem.
That leaves a small EC2 instance.

## Decision

### 1. Business-hours window on the existing lease

`netbird-lease-teardown.yml` gains a recurring window next to the existing
one-off lease. A new repo variable holds it:

```text
NETBIRD_HOURS = "10:00-23:00 America/New_York"
```

The stack is "wanted up" when either the one-off lease
(`NETBIRD_KEEP_UP_FROM/UNTIL`, unchanged) is active or the current time is
inside the window. To absorb the cold start, the workflow treats the window
as opening 20 minutes early (09:40 local), so the server and the tablets'
reconnects are done by 10:00. The window closes at 23:00, and the next
15-minute check tears down. An empty or unset variable disables the window,
which returns ADR-037's behavior exactly.

The window is evaluated with Python's `zoneinfo`, so daylight saving time
moves with the local clock and no cron expression has to be rewritten twice
a year. EventBridge Scheduler stays the primary clock and the GitHub cron
the fallback, as in ADR-037; neither needs to change, because both only
dispatch the workflow, and the workflow owns the decision.

The workflow also starts and stops the monitor instance (section 2) on the
same decision, after the server is up and before it is torn down.

`netbird.sh status` shows the window and whether it is open. `netbird.sh up`
still works outside the window as a one-off lease, but outside the window
it does not start the monitor: off-hours use is operator work, not
something to alert on.

### 2. Monitor host: one EC2 instance in the NetBird account

- `t4g.nano` (2 vCPU burstable, 0.5 GiB, ARM), Amazon Linux 2023, in one of
  the existing public subnets of the NetBird VPC (`10.0.128.0/20`). A
  public IPv4 address is needed for outbound access (NetBird management,
  ntfy, AWS APIs), because the VPC has no NAT gateway (ADR-037).
- **No inbound security group rules at all.** NetBird is outbound-initiated,
  and the stateful security group admits the return traffic of the
  WireGuard hole punch. When a direct path fails, traffic goes through the
  NetBird relay, which is also outbound.
- No SSH key. Shell access is through SSM Session Manager, which needs
  `ssm`, `ssmmessages` and `ec2messages` added to the SCP allow list. That
  SCP change ships in its own PR in `infra/mgmt/org`.
- IMDSv2 required, encrypted gp3 root volume (8 GiB), detailed monitoring
  off.
- **Stopped outside business hours, not terminated.** NetBird's peer state
  and ADB's state live on the root volume, so a stop/start keeps the peer
  identity and its NetBird IP. A stopped instance costs only its EBS volume,
  and an auto-assigned public IPv4 is released while stopped, so it is not
  billed then.
- Code and configuration go in through `user_data` (a templated cloud-init
  script with the monitor's Python embedded), with
  `user_data_replace_on_change = true`. A code change replaces the instance.
  That is acceptable because enrollment is automatic (section 3) and there
  is no other state to keep.

Module: `infra/modules/tablet_monitor`. Live wiring:
`infra/live/netbird/monitor.tf`.

### 3. NetBird identity and access

- The monitor enrolls with a NetBird **setup key** (one use, not ephemeral),
  stored in Secrets Manager in the NetBird account. A setup-key peer has no
  login expiration, so the monitor never needs an interactive login.
- It joins a new group, `monitors`.
- Two new access policies, both one way:
  - `monitors` to `admin-tablets`: TCP, all ports. ADB needs 5555 plus
    Wireless debugging's random port (30000 to 49999 on the tablets seen so
    far) during reboot recovery.
  - the operator's group (the source group of the existing Mac-to-tablet
    policy) to `monitors`: TCP 8080, for the status page.

  Tablets still cannot open connections to anything, which keeps ADR-037's
  rule that the tablets are targets, never sources.
- The groups, policies and setup key are made in the NetBird dashboard once
  and recorded in the module README. NetBird's REST API can do the same,
  but managing NetBird objects from Terraform is not worth a new provider
  for three objects.

### 4. ADB identity: reuse the operator's key

The ADB client authenticates with an RSA key pair, and each tablet keeps a
list of trusted keys. Wireless debugging pairing stores the same key. The
monitor loads the operator's existing ADB key pair from Secrets Manager into
`~/.android/`, so every tablet that already trusts the Mac also trusts the
monitor. No tablet has to approve a new key.

Trade-off: one key on two hosts. Revoking ADB authorizations on a tablet
cuts off both, and a leak from either host exposes both. The key is only
useful from inside the NetBird overlay, and the alternative (a monitor key
that each tablet approves once over `scrcpy`) is still available if the
blast radius ever matters more than setup effort.

### 5. Checks

Every 5 minutes (systemd timer), for each tablet in the inventory:

| Check | Red when | How |
| --- | --- | --- |
| NetBird | peer not connected | `netbird status --json` on the monitor |
| ADB | no ADB session after recovery | same logic as `tablet-adb.sh`: 5555, then mDNS, then a port scan |
| App running | kiosk app has no process | `pidof <package>` |
| App in front | kiosk app is not the top resumed activity | `dumpsys activity activities` |
| Printer | the tablet's expected printer is not seen | per-tablet rule (below) |
| Google | no `com.google` account on the device | `dumpsys account` |
| Backend connection | the kiosk app has no established TCP connection on 443 | `/proc/net/tcp` and `/proc/net/tcp6`, filtered by the app's UID |
| Live label | the app's "Live" status label is not on screen | `uiautomator dump` text (only when the app is in front) |

Two more values are shown on the page as information only. They never turn
a tablet red:

| Value | How |
| --- | --- |
| Active order count | the order count text in the same `uiautomator dump` |
| Last order seen | the monitor's own record of the last time the count rose |

**What the kiosk app exposes, and what it does not.** Checked on the first
tablet on 2026-11-20 (app version 2.0.0, React Native, release build):

- The app logs its order-server connection to logcat under the
  `ReactNativeJS` tag (`[VenueSocket] Connected`, `Transport upgraded`).
  The monitor records the time of the last such line as information. The
  log alone cannot say the connection is up now (it is a ring buffer, and no
  disconnect line has been observed yet), so the red check uses the live
  socket table instead.
- The app holds long-lived TLS connections to its backend (Google Cloud
  addresses). An established socket owned by the app's UID is the
  "connected" signal. The check does not pin backend IP addresses, because
  those can change behind a load balancer.
- The screen text, read with `uiautomator dump`, includes the venue name, a
  "Live" status label, the active order count, and the order list. This is
  the only source for order data on the device: the app's private storage
  cannot be read, because the build is not debuggable (`run-as` fails) and
  the tablets are not rooted. The app posts no notifications and logs no
  order events.
- The expected label text ("Live") and the order-count pattern are set per
  tablet in the inventory, with those values as defaults, so an app update
  that renames them is a secret update, not a code change.

**Limits of the screen-based values.** They need the app in front, so they
are unknown whenever the "App in front" check fails. An app update that
changes the layout can break them, which is one reason only the "Live"
label is allowed to turn a tablet red. "Last order seen" misses any order
that arrives and is closed between two 5-minute runs. The reliable source
for last order time and ID is the app's backend, if an API to it becomes
available; that would replace the screen-based values.

**Privacy.** The screen text contains venue and customer data. The monitor
keeps only the label's presence, the count, and timestamps. It never stores
or sends order details, customer names, or the raw dump.

Checks short-circuit: if NetBird is offline, the ADB-based checks are
reported as unknown, not as five extra failures.

**Printer rules are per tablet**, because each site prints differently.
The inventory gives each tablet one rule:

- `bluetooth:<name substring>`: a bonded Bluetooth device whose name matches.
- `usb:<product substring>`: an attached USB device whose product matches.
- `plugin:<package>`: an installed and enabled Android print-service plugin.
- `none`: the check is skipped.

Wi-Fi printers added through Android's built-in print service do not show up
over ADB until a print is attempted. For those tablets the rule is `plugin:`
(the plugin is installed and enabled) or `none`; the check cannot prove the
printer itself is reachable. This is a known gap.

**The Google check sees presence, not health.** It goes red when the account
is removed. It cannot see an account that is present but needs
re-authentication (password change, security hold), because that state is
not exposed to `adb shell` without root. A deeper check (for example,
parsing sync errors from `dumpsys content`) can come later if a real failure
shows the gap matters.

### 6. Alerting

- **Hysteresis.** A tablet turns red after two consecutive failing runs
  (about 10 minutes). It turns green after one passing run. This rides out a
  reboot (about 3 minutes end to end) and brief Wi-Fi drops.
- **Grace period.** For the first 15 minutes after the monitor starts each
  day, nothing alerts, because tablets rejoin NetBird with a backoff after
  the overnight teardown.
- ntfy alerts are sent on transitions only: green to red (the failed checks
  in the message), and red to green (recovered). The topic is a random,
  unguessable name stored in Secrets Manager, never in the repo.
- **A daily "monitor up" message** goes out when the grace period ends, with
  the count of green and red tablets. Its absence on a business day is the
  signal that the monitor itself is broken. That is a cheap dead-man's
  switch with no extra infrastructure. A real one (an external heartbeat
  check) is a follow-up.

### 7. Status page

- The monitor writes `status.json` and a static `index.html` after each run.
  A small HTTP server serves them on port 8080, bound to the monitor's
  NetBird interface address only, so the page is reachable only from inside
  the overlay (section 3), and only from the operator's group.
- The page draws a simple map: the server and the monitor in the middle,
  one node per tablet, colored green, red or gray (unknown/outside hours),
  with each check's result, the last check time, and the last few
  transitions. It reloads itself every 60 seconds; the data refreshes every
  5 minutes.
- **Each tablet that is online on NetBird gets a copy button** for the
  command that opens it in `scrcpy` from the operator's Mac:

  ```text
  TABLET_HOST=<netbird-ip> tablet-adb.sh scrcpy
  ```

  The wrapper is used instead of a bare `scrcpy -s <ip>:5555` because it
  first recovers ADB on 5555 when the tablet has just rebooted. The bare
  form is shown under it for machines that do not have the wrapper. The
  button copies with a hidden text area and `document.execCommand("copy")`,
  because the page is served over plain HTTP on the overlay address, and
  browsers expose `navigator.clipboard` only on HTTPS or `localhost`. When
  NetBird reports a tablet offline, the button is disabled, since the
  command could not connect.
- **Each tablet with a working ADB session gets a Reboot button.** It is
  the page's only state-changing action, and the only reason the HTTP
  server is more than a static file server. The command it runs is fixed
  (`adb -s <ip>:5555 reboot` for a tablet in the inventory); the request
  carries only the tablet's inventory name, never a command or an address.
  The equivalent command is shown for copying too, for use from the Mac.

  The page has no login, so the endpoint is protected against requests the
  operator did not mean to send:

  - **Cross-site requests.** Any website the operator's browser loads can
    send requests to the monitor's overlay address while the Mac is on
    NetBird. The reboot endpoint accepts only `POST`, requires a random
    token that the monitor puts into the page it serves (generated at
    start, rotated daily), and rejects any request whose `Origin` is not
    the monitor's own address. Other origins cannot read the page, so they
    cannot learn the token.
  - **DNS rebinding.** The server rejects any request whose `Host` header
    is not the monitor's NetBird IP or NetBird DNS name.
  - **Mistakes.** The button asks for confirmation, naming the tablet. Each
    tablet can be rebooted at most once every 10 minutes.
  - **Expected red.** A reboot pauses that tablet's alerts for 10 minutes
    (a reboot and ADB recovery took about 3 minutes in testing). It sends
    an ntfy message when the reboot is requested, so every reboot leaves
    a record, and the usual recovery message follows when the tablet is
    green again.

  **The limit.** A remote reboot needs a working ADB session. A tablet whose
  ADB is unreachable, or that is offline on NetBird, cannot be rebooted from
  here, and those are the cases where a reboot would help most. An
  unrooted tablet without a device-management (MDM) enrollment offers no
  other remote reboot path; NetBird has none. For those cases the alert is
  the signal to call the site.
- There is no login, because NetBird membership is the access control. A
  public URL was considered and rejected: it would add an internet-facing
  endpoint that shows device names, account names and network addresses.

### 8. Inventory lives outside the repo

The tablet list (name, NetBird address, kiosk app package, printer rule) is a
JSON document in Secrets Manager in the NetBird account. It holds site names
and per-site details that do not belong in a public repository. Adding a
tablet is a secret update plus a monitor restart, not a code change.

## Consequences

### Positive

- Problems surface within about 10 minutes during business hours, without
  the operator's Mac.
- The server's cost falls from 24/7 to 13 hours a day, and the off-hours
  teardown keeps working exactly as ADR-037 designed.
- No new tablet-side setup: the monitor reuses the existing ADB trust and
  the existing on-device recovery.
- The page is private by construction (overlay only, operator's group only).
- A tablet that is up but misbehaving can be rebooted from the page, from
  any device on the operator's NetBird group.

### Negative

- A new always-running component (during business hours) that can break
  silently. The daily "monitor up" message only partly covers that.
- The operator's ADB key is now on two hosts.
- The page is no longer read-only: the reboot endpoint is a state-changing
  action without a login, protected by a page token, an `Origin` check and
  a `Host` check instead.
- Two checks are weaker than their names suggest: the Google check sees
  presence, not authentication health, and the printer check cannot prove a
  Wi-Fi printer is reachable.
- Code changes replace the instance (user data), and the replacement
  enrolls as a new NetBird peer with a new IP. The old peer must be removed
  from the dashboard by hand. A one-use setup key per instance generation
  keeps this explicit, at the cost of one manual step per code change.

### Cost

us-east-1 on-demand prices, 13 hours a day (09:40 to 23:00, rounded up):

| Item | Monthly |
| --- | --- |
| NetBird server (NLB + Fargate), about $30/month at 24/7 | about $16 |
| Monitor: t4g.nano, 13 h/day | about $1.70 |
| Monitor: public IPv4, 13 h/day | about $2 |
| Monitor: 8 GiB gp3 | about $0.65 |
| Secrets Manager: 4 new secrets (setup key, ADB key, ntfy topic, inventory) | about $1.60 |
| **Total** | **about $22** |

## Implementation Order

1. This ADR.
2. Business-hours window in `netbird-lease-teardown.yml`, plus the
   `netbird.sh status` display. Useful on its own: it gives tablets a
   reliable rejoin window even before the monitor exists.
3. SCP change in `infra/mgmt/org`: allow `ssm`, `ssmmessages`,
   `ec2messages`.
4. NetBird dashboard: `monitors` group, the two policies, a one-use setup
   key. Store the setup key, the ADB key pair, the ntfy topic and the
   inventory in Secrets Manager (manual, documented commands, no values in
   the repo).
5. `infra/modules/tablet_monitor` and `infra/live/netbird/monitor.tf`.
   Apply, then verify each red condition by causing it on purpose (stop the
   kiosk app, bring another app to the front, disconnect NetBird on a
   tablet, unpair a printer).
6. Lease workflow starts and stops the instance with the window.

## References

- ADR-037: self-hosted NetBird server, dedicated account, lease teardown.
- AWS Fargate task definition parameters, Linux capabilities
  (`SYS_PTRACE` is the only addable capability).
- NetBird client documentation: netstack (userspace) mode and its SOCKS5
  proxy.
- Android `adb` Wireless debugging: pairing and the `_adb-tls-connect._tcp`
  mDNS service.
