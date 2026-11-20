#!/bin/bash
# tablet-adb.sh: get ADB on the tablet back to TCP 5555 over NetBird, then
# optionally start scrcpy. Built for unattended recovery after a tablet
# reboot (ADR-037 spike, 2026-11-19).
#
# Usage:
#   tablet-adb.sh            connect (recover 5555 if needed)
#   tablet-adb.sh scrcpy     connect, then start scrcpy
#
# How recovery works: after a reboot, ADB TCP mode (5555) is off. The
# Automate flow on the tablet turns Wireless debugging on (and keeps it on).
# Wireless debugging listens on a random high port, which this script finds
# (mDNS on the same LAN, otherwise a TCP scan of the tablet's NetBird
# address), connects to it using the one-time pairing from setup, and runs
# `adb tcpip 5555`. Verified over NetBird: pairing and the TLS connect port
# both accept connections on the NetBird interface.
#
# Set the target with TABLET_HOST (the tablet's NetBird IP or DNS name).
# Needs adb, scrcpy (for the scrcpy action) and python3.
# Docs: docs/runbooks/netbird/tablet-setup.md
set -uo pipefail

HOST="${TABLET_HOST:?Set TABLET_HOST to the tablet NetBird IP, for example TABLET_HOST=100.96.1.2}"
SCAN_FROM=30000
SCAN_TO=49999

ok_5555() {
  adb connect "$HOST:5555" >/dev/null 2>&1
  adb -s "$HOST:5555" shell true >/dev/null 2>&1
}

# Prints every Wireless debugging port seen on the LAN. With several tablets
# on one network these belong to different devices, so recover() tries each
# against HOST and falls back to the scan if none of them is HOST's.
find_port_mdns() {
  adb mdns services 2>/dev/null | awk '/_adb-tls-connect\._tcp/ {print $NF}' | sed -E 's/.*://' | sort -u
}

# Prints open TCP ports on HOST in the scan range, fastest first.
find_ports_scan() {
  python3 - "$HOST" "$SCAN_FROM" "$SCAN_TO" <<'PY'
import asyncio, sys
host, lo, hi = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
sem = asyncio.Semaphore(600)
async def probe(p):
    async with sem:
        try:
            _, w = await asyncio.wait_for(asyncio.open_connection(host, p), 1.5)
            w.close()
            print(p, flush=True)
        except Exception:
            pass
async def main():
    await asyncio.gather(*(probe(p) for p in range(lo, hi + 1)))
asyncio.run(main())
PY
}

try_ports() {
  local port
  for port in "$@"; do
    if adb connect "$HOST:$port" 2>&1 | grep -q "connected to"; then
      echo "Wireless debugging found on port $port; switching ADB to 5555..."
      adb -s "$HOST:$port" tcpip 5555 >/dev/null 2>&1
      adb disconnect "$HOST:$port" >/dev/null 2>&1
      for _ in $(seq 1 10); do
        sleep 2
        if ok_5555; then return 0; fi
      done
    fi
  done
  return 1
}

recover() {
  echo "5555 not answering; looking for the Wireless debugging port on $HOST..."
  # shellcheck disable=SC2046
  try_ports $(find_port_mdns) && return 0
  echo "No usable mDNS answer (other LAN, or another tablet's port); scanning $SCAN_FROM-$SCAN_TO over NetBird..."
  # shellcheck disable=SC2046
  try_ports $(find_ports_scan)
}

if ok_5555 || recover; then
  echo "ADB ready: $HOST:5555 ($(adb -s "$HOST:5555" shell getprop ro.product.model 2>/dev/null | tr -d '\r'))"
else
  echo "Could not reach ADB on $HOST. Check: NetBird connected on both ends (netbird status)," >&2
  echo "server up (netbird.sh status), Automate flow running, Wireless debugging on." >&2
  exit 1
fi

if [ "${1:-}" = "scrcpy" ]; then
  exec scrcpy -s "$HOST:5555" --stay-awake
fi
