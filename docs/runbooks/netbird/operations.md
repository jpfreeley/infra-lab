# NetBird Tablets: Operations

Day-to-day use, what to do when something is red, and the known gaps.

## Daily use

All commands from `scripts/netbird/` on a Mac in `admin-macs`.

| Task | Command |
| --- | --- |
| Is anything up? | `./netbird.sh status` |
| Bring everything up for 2 hours | `./netbird.sh up 2h` (`30m`, `4h`, `2d` also work; running it again replaces the lease) |
| Check all tablets now | `./netbird.sh checkin` |
| Open a tablet's screen | `TABLET_HOST=<ip> ./tablet-adb.sh scrcpy` |
| Just connect ADB | `TABLET_HOST=<ip> ./tablet-adb.sh` |
| Check a tablet's settings | `ADB_SERIAL=<ip>:5555 ./tablet-setup.sh check` |
| Done, tear down now | `./netbird.sh down` |

If you forget `down`, the lease ends on its own and the next 15-minute
check tears everything down. An open `scrcpy` session keeps working after
the server goes down; only new connections and rebooted tablets need it.

## When a tablet is red

Start with `./netbird.sh up 1h` if nothing is up, then open the status
page.

| Red check | Likely cause | Fix |
| --- | --- | --- |
| NetBird online | tablet off, out of battery, no Wi-Fi, or NetBird VPN off | call the site: is it on, charging, on Wi-Fi? Its event log (once back) shows `power` and `wifi` events. |
| ADB reachable | Wireless debugging off after a reboot and the Automate flow not running | `TABLET_HOST=<ip> ./tablet-adb.sh` (recovers 5555 if Wireless debugging is on). If not, someone at the site opens Automate and starts the flow. |
| App running | kiosk app crashed or was force-stopped | Automate restarts it within 5 minutes if the flow runs. Otherwise start it with `scrcpy`, or `adb -s <ip>:5555 shell monkey -p com.plateraterestaurantsv2 1`. |
| App in front | staff left another screen open | same as above; Automate brings it back after 5 minutes away |
| Printer | printer off, unpaired, or unplugged | call the site. Re-pair with `scrcpy` if needed. |
| Google account | the account was removed | sign in again at the tablet (needs the 2-step code) |
| Backend connection | the app lost its server connection (site internet, or the app's backend) | check the site's internet; restart the app; if every tablet is red on this, it is the app's backend |
| Live label | app is logged out of the venue, or shows an error screen | open with `scrcpy` and look |

Reboot from the page (or `adb -s <ip>:5555 reboot`) is the general fix for
a tablet that is online but stuck. It comes back in about 3 minutes.

## When the stack misbehaves

| Symptom | Check | Fix |
| --- | --- | --- |
| No "Tablet monitor up" message near a check-in | `gh run list --workflow netbird-lease-teardown.yml` and `--workflow netbird-toggle.yml` | A failed toggle run: open it and read the failed step. No runs at all: the workflow may be disabled (`gh workflow list --all`), or both clocks failed (Lambda log in the management account, expired token). |
| `netbird.sh up` says not ready after 15 minutes | ECS service events, task logs (CloudWatch `/ecs/...netbird...`) | usually a task that failed to start: secrets missing or a bad image pin |
| `netbird.sh` says DOWN, but others can connect | Mac DNS cache from while the record was deleted | `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` (the script prints this hint when it detects it) |
| Monitor up, page does not load | `netbird status` on the Mac lists `tablet-monitor` | Mac not in `admin-macs`, or the tunnel is idle (load the page twice) |
| Monitor never joins NetBird | `/var/log/netbird/client.log` on the monitor | `setup key is invalid`: store a new one-use key, delete the stale peer, restart the instance |
| Monitor restarts in a loop | `journalctl -u tablet-monitor` | a code error after an update; the service keeps the last good copy if the new one does not compile, but runtime errors need a fix PR |

## Routine care

| When | What |
| --- | --- |
| Each new tablet | [tablet-setup.md](tablet-setup.md), including the inventory and the monitor's ADB key |
| Each new person | [adding-people.md](adding-people.md) |
| Before the trigger token expires | new fine-grained token, store it ([github-setup.md](github-setup.md) step 5) |
| Monthly | AWS cost for the NetBird account (expected about $10 to $12) |
| NetBird upgrades | bump the image pins (`netbird_server` module) and the monitor's client pin in a PR; the tablets' NetBird app updates itself from the Play Store, so keep the server reasonably current |
| After an app update | check that the "Live" label and order count still read on the status page |

## Known gaps

- **Silence is ambiguous.** A green check-in sends nothing. A missing
  "Tablet monitor up" message is the only sign that a check-in did not
  happen. There is no external heartbeat yet.
- **Detection is slow.** A tablet that fails just after a check-in is
  reported up to about 6 hours later.
- **No alarm on the trigger Lambda.** An expired GitHub token shows up only
  as late teardowns (the GitHub cron fallback still runs) and as errors in
  the Lambda's log.
- **The monitor and the first operator share one ADB key.** Revoking ADB
  authorizations on a tablet cuts off both.
- **A tablet that is offline or has no ADB cannot be rebooted remotely.**
  An unrooted tablet without device management has no other path; the
  fallback is a phone call to the site.
- **Google and printer checks are partial** (see [monitoring.md](monitoring.md)).
- **Screen-based values depend on the app's layout.** The reliable source
  for order data would be the app's backend, if an API becomes available.
