# tablet_monitor

One EC2 instance that joins a NetBird overlay as a peer and checks kiosk
tablets over ADB at scheduled check-ins (ADR-038). It sends a ntfy message
when a tablet is red and serves a status page on its NetBird address only.

## What runs on the instance

- **NetBird client** (pinned release, SHA-256 verified), enrolled once with a
  one-use setup key read from Secrets Manager.
- **adb** from Android platform-tools (pinned, SHA-256 verified), using the
  ADB key pair the tablets already trust (Secrets Manager).
- **`files/monitor.py`** as the `tablet-monitor` systemd service. Standard
  library only. It runs the check-ins on its own clock (scheduled times, a
  check-in at start-up when the boot is not part of a scheduled window, and
  "Check now" from the page), and serves the status page on port 8080 of the
  NetBird interface.

Bootstrap output: `/var/log/tablet-monitor-bootstrap.log`. Service log:
`journalctl -u tablet-monitor`.

## Access

No SSH key and no inbound rules. Shell access:

```bash
aws ssm start-session --target <instance id>
```

The status page is `http://tablet-monitor.<netbird dns domain>:8080/`, reachable
from peers allowed by the `Mac2Monitor` NetBird policy.

## Secrets (values set out of band)

`infra/live/netbird/monitor_secrets.tf` creates the four secrets and documents
the commands that fill them: setup key, ADB key pair, ntfy topic, inventory.

Inventory format:

```json
{"tablets": [{
  "name": "tablet1",
  "site": "Site name",
  "host": "100.x.y.z",
  "package": "com.example.kiosk",
  "printer": "none | bluetooth:<name> | usb:<product> | plugin:<package>",
  "live_label": "Live",
  "orders_pattern": "(\\d+) orders?",
  "event_log": "/sdcard/Documents/tablet-events.log"
}]}
```

Only `name` and `host` are required. Inventory changes apply on the next
service restart (`systemctl restart tablet-monitor`) or the next start.

## Replacing the instance

Any change to `files/monitor.py`, the bootstrap template or the pinned
versions changes the user data, which replaces the instance. The new
instance needs a new one-use setup key:

1. In the NetBird dashboard, create a new setup key (one use, not ephemeral,
   auto-group `monitors`) and store it in the setup-key secret.
2. Apply.
3. Delete the old `tablet-monitor` peer in the dashboard. The new peer gets a
   new NetBird IP, so use the DNS name for the page.

## Testing monitor.py locally

On a machine that is on NetBird and has adb:

```bash
INVENTORY_FILE=inventory.json NTFY_TOPIC=test DRY_RUN=1 BIND=127.0.0.1 \
  python3 files/monitor.py --once
```

## Limits

- User data is limited to 16 KB after decoding. The gzipped bootstrap with
  `monitor.py` inside is about 13.5 KB; a much larger `monitor.py` would need
  another delivery path (for example S3).
- x86_64 only (the Linux adb is not published for ARM).
