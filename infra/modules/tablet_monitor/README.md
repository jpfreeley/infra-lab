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
  library only. Terraform uploads it to a KMS-encrypted S3 bucket; the
  service downloads it at every start (`ExecStartPre`, checked with
  `py_compile`, last good copy kept on failure). The instance boots at every
  check-in, so a code change reaches it at the next check-in. To deploy at
  once: `systemctl restart tablet-monitor` over SSM. It runs the check-ins on its own clock (scheduled times, a
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

## Updating the code

Change `files/monitor.py` and apply. Only the S3 object changes; the
instance is not replaced. The new code runs from the next service start.

## Replacing the instance

Changes to the bootstrap template, the pinned versions or the instance
settings change the user data, which replaces the instance. The new
instance needs a new one-use setup key:

1. In the NetBird dashboard, delete the old `tablet-monitor` peer, so the new
   one gets the same DNS name.
2. Create a new setup key (one use, not ephemeral, auto-group `monitors`)
   and store it in the setup-key secret.
3. Apply.

## Testing monitor.py locally

On a machine that is on NetBird and has adb:

```bash
INVENTORY_FILE=inventory.json NTFY_TOPIC=test DRY_RUN=1 BIND=127.0.0.1 \
  python3 files/monitor.py --once
```

## Limits

- x86_64 only (the Linux adb is not published for ARM).
