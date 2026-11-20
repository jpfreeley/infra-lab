#!/bin/bash
# netbird.sh: check/lease/toggle the self-hosted NetBird server (ADR-037, ADR-038)
#
# Usage:
#   netbird.sh status            readiness + current uptime lease
#   netbird.sh up [duration]     set a lease (default 2h; e.g. 30m, 4h, 2d) and
#                                bring the stack up if it is down. Run again to
#                                extend: the lease is replaced, not stacked.
#   netbird.sh down              end the lease now and tear the stack down
#   netbird.sh checkin           run a tablet check-in now and print every
#                                tablet's result (ADR-038). If the monitor
#                                is up, presses its "Check now"; otherwise
#                                sets a 1h lease, brings everything up, and
#                                waits for the check-in the monitor runs at
#                                start. Takes about 12 to 30 minutes.
#
# The lease is two repo variables (NETBIRD_KEEP_UP_FROM/UNTIL) read by
# .github/workflows/netbird-lease-teardown.yml every 15 minutes. While a
# lease is active the workflow keeps the stack up (and brings it back if it
# went down); once it expires, the next check tears it down.
#
# Needs: gh (logged in as a user with write access to the repo below),
# python3 3.9+, curl, dig, and the NetBird client (for checkin/status).
#
# Settings (environment variables, defaults are the infra-lab deployment):
#   NETBIRD_REPO      GitHub repo that holds the workflows and lease variables
#   NETBIRD_HOST      public name of the NetBird server
#   NETBIRD_GH_USER   if set, `gh auth switch` to this account first (for
#                     machines with more than one gh account logged in)
#
# Docs: docs/runbooks/netbird/README.md
set -uo pipefail

REPO="${NETBIRD_REPO:-jpfreeley/infra-lab}"
READY_HOST="${NETBIRD_HOST:-netbird.lintwiselabs.com}"
READY_URL="https://$READY_HOST/oauth2/.well-known/openid-configuration"

# Prints the HTTP code of the readiness probe. If the Mac's own resolver
# cannot find the host, retries through a public resolver (1.1.1.1). After a
# down/up cycle macOS can keep a cached "no such name" answer from while the
# Route53 record was deleted, which made `up` wait 15 minutes and report
# "not ready" against a healthy server (2026-11-20). A 200 through the
# fallback prints "200-dns" so callers can tell the user to flush the cache.
check_ready() {
  # curl -w already prints 000 when the connection fails, so the fallback
  # must not print it again (that produced "HTTP 000000").
  local code ip
  code=$(curl -sS -m 8 -o /dev/null -w "%{http_code}" "$READY_URL" 2>/dev/null)
  code="${code:-000}"
  if [ "$code" = "000" ] && ! dscacheutil -q host -a name "$READY_HOST" | grep -q address; then
    ip=$(dig +short "$READY_HOST" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
    if [ -n "$ip" ]; then
      code=$(curl -s -m 8 -o /dev/null -w "%{http_code}" --resolve "$READY_HOST:443:$ip" "$READY_URL" 2>/dev/null)
      [ "$code" = "200" ] && code="200-dns"
    fi
  fi
  echo "${code:-000}"
}

DNS_HINT="Server is up, but this Mac's DNS cache still has the old \"no such name\" answer.
Flush it so the NetBird client can reconnect: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"

# Prints an ISO 8601 UTC timestamp `duration` from now. Accepts Nm, Nh, Nd.
until_from_duration() {
  python3 - "$1" <<'PY'
import datetime, re, sys
m = re.fullmatch(r"(\d+)([mhd])", sys.argv[1].strip().lower())
if not m:
    sys.exit("duration must look like 30m, 4h or 2d")
n, unit = int(m.group(1)), m.group(2)
delta = {"m": datetime.timedelta(minutes=n), "h": datetime.timedelta(hours=n), "d": datetime.timedelta(days=n)}[unit]
print((datetime.datetime.now(datetime.timezone.utc) + delta).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

lease() {
  gh variable list --repo "$REPO" --json name,value \
    --jq '.[] | select(.name|startswith("NETBIRD_KEEP_UP") or . == "NETBIRD_CHECKINS") | "\(.name)=\(.value)"' 2>/dev/null
}

# Same rule as netbird-lease-teardown.yml (ADR-038): each check-in opens a
# window from 40 minutes before to 15 minutes after, zoneinfo for DST.
# Prints open, closed, off or invalid.
window_state() {
  python3 - "$1" <<'PY2'
import datetime, re, sys, zoneinfo
spec = sys.argv[1].strip()
if not spec:
    print("off"); sys.exit()
m = re.fullmatch(r"(\d{1,2}:\d{2}(?:\s*,\s*\d{1,2}:\d{2})*)\s+(\S+)", spec)
try:
    tz = zoneinfo.ZoneInfo(m.group(2))
    times = []
    for t in m.group(1).split(","):
        h, mi = (int(x) for x in t.strip().split(":"))
        assert 0 <= h <= 23 and 0 <= mi <= 59
        times.append(h * 60 + mi)
except Exception:
    print("invalid"); sys.exit()
now = datetime.datetime.now(tz); minute = now.hour * 60 + now.minute
print("open" if any((minute - (t - 40)) % 1440 < 55 for t in times) else "closed")
PY2
}

# The tablet monitor's status page (ADR-038), over NetBird. Prints the base
# URL of the first monitor peer that answers, or nothing.
monitor_url() {
  local ip
  for ip in $(netbird status --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
for p in (d.get("peers") or {}).get("details") or []:
    if (p.get("fqdn") or "").startswith("tablet-monitor"):
        print(p["netbirdIp"].split("/")[0])'); do
    # The first request also wakes a lazy (Idle) NetBird tunnel; retry once.
    if curl -s -m 8 -o /dev/null "http://$ip:8080/status.json" 2>/dev/null ||
       curl -s -m 8 -o /dev/null "http://$ip:8080/status.json" 2>/dev/null; then
      echo "http://$ip:8080"
      return 0
    fi
  done
  return 1
}

# Waits for the running or next check-in to finish and prints the result.
wait_checkin() {
  python3 - "$1" "$2" <<'PY2'
import json, sys, time, urllib.request
base, since = sys.argv[1], float(sys.argv[2])
last_phase, deadline = None, time.time() + 45 * 60
while time.time() < deadline:
    try:
        d = json.load(urllib.request.urlopen(base + "/status.json", timeout=10))
    except Exception as e:
        print("  monitor unreachable (%s), retrying" % e.__class__.__name__); time.sleep(30); continue
    ci = d.get("checkin")
    phase = ci and "%s: %s" % (ci["kind"], ci["phase"])
    if phase and phase != last_phase:
        print("  " + time.strftime("%H:%M:%S") + " " + phase, flush=True); last_phase = phase
    done = [h for h in d.get("history", []) if h["at"] >= since]
    if not ci and done:
        h, labels = done[0], d.get("labels", {})
        print("\nCheck-in finished %s (%s):" % (time.strftime("%H:%M", time.localtime(h["at"])), h["kind"]))
        for t in d["tablets"]:
            # The check-in verdict needs a check to fail in BOTH runs; the
            # latest run alone can differ (for example someone on another
            # screen for a minute), so show that separately.
            failed = h["red"].get(t["name"])
            name = t["name"] + (" (" + t["site"] + ")" if t.get("site") else "")
            if failed:
                print("  RED    %s: %s" % (name, ", ".join(labels.get(k, k) for k in failed)))
            else:
                latest = [labels.get(k, k) for k, v in t["checks"].items() if v["ok"] is False]
                print("  green  %s%s" % (name, ("  (latest run only: " + ", ".join(latest) + " failed)") if latest else ""))
        print("\nPage: " + base + "/")
        sys.exit(1 if h["red"] else 0)
    time.sleep(30)
print("No finished check-in after 45 minutes; see " + base + "/")
sys.exit(2)
PY2
}

ACTION="${1:-status}"
if [ -n "${NETBIRD_GH_USER:-}" ]; then
  gh auth switch --user "$NETBIRD_GH_USER" >/dev/null 2>&1 || true
fi

case "$ACTION" in
  status)
    code=$(check_ready)
    case "$code" in
      200) echo "UP (HTTP 200)" ;;
      200-dns) echo "UP (HTTP 200 via public DNS)"; echo "$DNS_HINT" ;;
      *) echo "DOWN (HTTP $code)" ;;
    esac
    l=$(lease); echo "${l:-no lease set}"
    checkins=$(sed -n 's/^NETBIRD_CHECKINS=//p' <<<"$l")
    if [ -n "$checkins" ]; then
      echo "Check-in window: $(window_state "$checkins") ($checkins; each -40/+15 min)"
    fi
    if murl=$(monitor_url); then echo "Tablet monitor: up ($murl/)"; else echo "Tablet monitor: not reachable"; fi
    ;;
  up)
    until=$(until_from_duration "${2:-2h}") || exit 2
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    gh variable set NETBIRD_KEEP_UP_FROM --repo "$REPO" --body "$now" >/dev/null
    gh variable set NETBIRD_KEEP_UP_UNTIL --repo "$REPO" --body "$until" >/dev/null
    echo "Lease set until $until"
    code=$(check_ready)
    if [ "$code" = "200" ] || [ "$code" = "200-dns" ]; then
      echo "Already up (HTTP 200)"
      [ "$code" = "200-dns" ] && echo "$DNS_HINT"
      exit 0
    fi
    echo "Down (HTTP $code), triggering netbird-toggle up..."
    gh workflow run netbird-toggle.yml -f action=up --repo "$REPO"
    echo "Workflow triggered, polling for ready..."
    for i in $(seq 1 60); do
      code=$(check_ready)
      if [ "$code" = "200" ] || [ "$code" = "200-dns" ]; then
        echo "READY after $((i * 15))s"
        [ "$code" = "200-dns" ] && echo "$DNS_HINT"
        exit 0
      fi
      sleep 15
    done
    echo "Not ready after 15 minutes; check: gh run list --repo $REPO --workflow netbird-toggle.yml"
    exit 1
    ;;
  checkin)
    since=$(date +%s)
    if url=$(monitor_url); then
      echo "Monitor is up ($url); starting a check-in now..."
      token=$(curl -s -m 10 "$url/" | sed -n 's/.*const TOKEN = "\([^"]*\)".*/\1/p')
      reply=$(curl -s -m 10 -X POST -H "Origin: $url" -H "Content-Type: application/json" \
        -d "{\"token\":\"$token\"}" "$url/api/checknow")
      echo "  $reply"
      case "$reply" in *"already running"*) echo "  Waiting for the running check-in instead." ;; esac
    else
      echo "Monitor not reachable; bringing everything up with a 1h lease."
      echo "The monitor runs a check-in when it starts (after the tablets rejoin)."
      "$0" up 1h || exit 1
      printf "Waiting for the monitor"
      for _ in $(seq 1 60); do
        url=$(monitor_url) && break
        printf "."; sleep 15
      done
      echo
      [ -n "${url:-}" ] || { echo "Monitor did not come up in 15 minutes; check the toggle workflow run." >&2; exit 1; }
      echo "Monitor is up ($url)."
    fi
    wait_checkin "$url" "$since"
    ;;
  down)
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    gh variable set NETBIRD_KEEP_UP_UNTIL --repo "$REPO" --body "$now" >/dev/null
    echo "Lease ended at $now"
    gh workflow run netbird-toggle.yml -f action=down --repo "$REPO"
    echo "Teardown triggered."
    ;;
  *)
    echo "Usage: netbird.sh {status|up [duration]|down|checkin}" >&2
    exit 2
    ;;
esac
