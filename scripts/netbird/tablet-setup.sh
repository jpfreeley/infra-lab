#!/bin/bash
# tablet-setup.sh: the ADB-side setup for a new Plate Rate tablet (NetBird +
# Automate + Plate Rate). The tablet-side UI steps that ADB cannot do are in
# docs/runbooks/netbird/tablet-setup.md
#
# Usage:
#   tablet-setup.sh check     read-only: show what is set and what is missing
#   tablet-setup.sh apply     set everything below, then switch ADB to TCP 5555
#
# Target: the only attached device, or set ADB_SERIAL (USB serial, or
# host:port from Wireless debugging). Every step is safe to run again.
#
# What "apply" sets:
#   - Automate: WRITE_SECURE_SETTINGS (needed to set adb_wifi_enabled),
#     POST_NOTIFICATIONS, "Display over other apps" (needed to start Plate
#     Rate from the background on Android 10+), all-files access (writes the
#     event log to /sdcard/Documents) and usage access (sees which app is in
#     front, for self-repair)
#   - Battery optimization off (deviceidle whitelist) for Automate, Plate
#     Rate and NetBird
#   - Stay awake while charging (stay_on_while_plugged_in = 7: AC, USB, wireless)
#   - Lock screen off (only works when no PIN/pattern is set)
#   - Auto-rotate on
#   - Wireless debugging on, then ADB TCP mode on port 5555
set -uo pipefail

AUTOMATE=com.llamalab.automate
PLATERATE=com.plateraterestaurantsv2
NETBIRD=io.netbird.client

ACTION="${1:-check}"
if [ -n "${ADB_SERIAL:-}" ]; then
  A=(adb -s "$ADB_SERIAL")
else
  n=$(adb devices | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
  if [ "$n" != "1" ]; then
    echo "Found $n ADB devices. Set ADB_SERIAL to pick one:" >&2
    adb devices -l >&2
    exit 2
  fi
  A=(adb)
fi
tsh() { "${A[@]}" shell "$@" 2>/dev/null | tr -d '\r'; }

mark() { if [ "$1" = "yes" ]; then printf '  [ok]      %s\n' "$2"; else printf '  [MISSING] %s\n' "$2"; fi; }
yn() { if eval "$1" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# The captured outputs below are read inside yn's eval strings.
# shellcheck disable=SC2034
check() {
  echo "Device: $(tsh getprop ro.product.model), Android $(tsh getprop ro.build.version.release), serial $(tsh getprop ro.serialno)"
  local pk wl
  pk=$(tsh pm list packages)
  wl=$(tsh dumpsys deviceidle whitelist)
  for p in $NETBIRD $AUTOMATE $PLATERATE; do
    mark "$(yn "grep -q 'package:$p\$' <<<\"\$pk\"")" "installed: $p"
  done
  # Capture first: piping long dumpsys output into grep -q breaks the pipe
  # when grep exits early, and pipefail then reports a false "missing".
  local dp ao
  dp=$(tsh dumpsys package $AUTOMATE)
  ao=$(tsh appops get $AUTOMATE SYSTEM_ALERT_WINDOW)
  mark "$(yn "grep -q 'WRITE_SECURE_SETTINGS: granted=true' <<<\"\$dp\"")" "Automate: WRITE_SECURE_SETTINGS"
  mark "$(yn "grep -q 'POST_NOTIFICATIONS: granted=true' <<<\"\$dp\"")" "Automate: notifications"
  mark "$(yn "grep -q ': allow' <<<\"\$ao\"")" "Automate: display over other apps"
  local fs us
  fs=$(tsh appops get $AUTOMATE MANAGE_EXTERNAL_STORAGE)
  us=$(tsh appops get $AUTOMATE GET_USAGE_STATS)
  mark "$(yn "grep -q ': allow' <<<\"\$fs\"")" "Automate: all-files access (event log, ADR-038)"
  mark "$(yn "grep -q ': allow' <<<\"\$us\"")" "Automate: usage access (foreground app, ADR-038)"
  for p in $AUTOMATE $PLATERATE $NETBIRD; do
    mark "$(yn "grep -q ',$p,' <<<\"\$wl\"")" "battery unrestricted: $p"
  done
  mark "$( [ "$(tsh settings get global stay_on_while_plugged_in)" = "7" ] && echo yes || echo no)" "stay awake while charging"
  mark "$( [ "$(tsh locksettings get-disabled)" = "true" ] && echo yes || echo no)" "lock screen off"
  mark "$( [ "$(tsh settings get global adb_wifi_enabled)" = "1" ] && echo yes || echo no)" "Wireless debugging on"
  mark "$( [ "$(tsh settings get system accelerometer_rotation)" = "1" ] && echo yes || echo no)" "auto-rotate on"
  # Report only: signing in to Google needs the password and 2-step code on the tablet.
  local ga
  ga=$(tsh dumpsys account | sed -n 's/.*Account {name=\(.*\), type=com.google}.*/\1/p' | head -1)
  mark "$( [ -n "$ga" ] && echo yes || echo no)" "Google account signed in${ga:+: $ga}"
  # Report only: each tablet prints differently, so list every printing path
  # instead of judging one. Android printing goes through print-service
  # plugins (com.android.bips is the built-in Mopria/IPP one; vendor plugins
  # such as HP or Epson show up as extra packages). Bluetooth and USB
  # printers are usually driven by the app itself.
  local ps dis bt usb
  ps=$(tsh dumpsys print | sed -n '/installed_services/,/actives_services/s/.*package_name=//p' | sort -u | tr '\n' ' ')
  dis=$(tsh settings get secure disabled_print_services)
  echo "  [info]    print plugins: ${ps:-none}${dis:+(disabled: $dis)}" | sed 's/(disabled: null)//'
  bt=$(tsh dumpsys bluetooth_manager | sed -n '/Bonded devices:/,/^$/p' | grep -vE 'Bonded devices:|^$' | sed -E 's/^ *([0-9A-F:]{17}) *(\[[^]]*\])? *//' | paste -sd ',' -)
  echo "  [info]    Bluetooth paired: ${bt:-none}"
  usb=$(tsh dumpsys usb | sed -n 's/.*product_name=//p' | grep -v '^null$' | sort -u | paste -sd ',' -)
  echo "  [info]    USB devices: ${usb:-none}"
  local nbip
  # NetBird on Android uses a VPN tun interface (tun0/tun1/...) with an
  # address in 100.64.0.0/10, not wt0 as on desktop.
  nbip=$(tsh ip -4 -o addr | awk '$2 ~ /^tun/ {split($4, a, "/"); split(a[1], o, "."); if (o[1] == 100 && o[2] >= 64 && o[2] <= 127) {print a[1]; exit}}')
  if [ -n "$nbip" ]; then
    echo "  NetBird IP: $nbip   (use: TABLET_HOST=$nbip scripts/netbird/tablet-adb.sh scrcpy)"
  else
    echo "  [MISSING] NetBird tunnel not up: is the NetBird app connected?"
  fi
  echo "  Not checkable over ADB (see tablet-setup.md): Automate flow imported and"
  echo "  running, Automate 'Run on system startup', NetBird Always-on VPN,"
  echo "  Force relay off, Wireless debugging 'Always allow on this network'."
}

apply() {
  local p
  for p in $NETBIRD $AUTOMATE $PLATERATE; do
    grep -q "package:$p\$" <<<"$(tsh pm list packages)" || { echo "Not installed: $p. Install it first." >&2; exit 1; }
  done
  echo "Granting Automate permissions..."
  "${A[@]}" shell pm grant $AUTOMATE android.permission.WRITE_SECURE_SETTINGS
  "${A[@]}" shell pm grant $AUTOMATE android.permission.POST_NOTIFICATIONS
  "${A[@]}" shell appops set $AUTOMATE SYSTEM_ALERT_WINDOW allow
  # Event log in /sdcard/Documents and the foreground-app check (ADR-038).
  "${A[@]}" shell appops set $AUTOMATE MANAGE_EXTERNAL_STORAGE allow
  "${A[@]}" shell appops set $AUTOMATE GET_USAGE_STATS allow
  echo "Turning off battery optimization..."
  for p in $AUTOMATE $PLATERATE $NETBIRD; do tsh dumpsys deviceidle whitelist +$p >/dev/null; done
  echo "Stay awake while charging..."
  "${A[@]}" shell settings put global stay_on_while_plugged_in 7
  echo "Lock screen off..."
  tsh locksettings set-disabled true >/dev/null
  if [ "$(tsh locksettings get-disabled)" != "true" ]; then
    echo "  Could not turn off the lock screen. Remove the PIN/pattern on the tablet, then run apply again."
  fi
  echo "Auto-rotate on..."
  "${A[@]}" shell settings put system accelerometer_rotation 1
  echo "Wireless debugging on..."
  "${A[@]}" shell settings put global adb_wifi_enabled 1
  echo
  check
  echo
  echo "Switching ADB to TCP 5555 (the USB/pairing connection drops after this)..."
  "${A[@]}" tcpip 5555
}

case "$ACTION" in
  check) check ;;
  apply) apply ;;
  *) echo "Usage: tablet-setup.sh {check|apply}" >&2; exit 2 ;;
esac
