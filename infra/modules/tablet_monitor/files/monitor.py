#!/usr/bin/env python3
"""Tablet monitor (ADR-038).

Runs on a NetBird peer that can reach the kiosk tablets over ADB. At each
check-in it checks every tablet twice, 10 minutes apart, sends one ntfy
message if any tablet failed the same check both times, and keeps the
latest results for a status page served on the NetBird address only.

Standard library only (Python 3.9+). Configuration comes from environment
variables; see CONFIG below. For a local dry run on a machine that is on
NetBird and has adb:

    INVENTORY_FILE=inventory.json NTFY_TOPIC=test DRY_RUN=1 BIND=127.0.0.1 \
        python3 monitor.py --once
"""

import asyncio
import datetime
import hmac
import http.server
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import time
import urllib.request
import zoneinfo

CONFIG = {
    "region": os.environ.get("AWS_REGION", "us-east-1"),
    "inventory_secret": os.environ.get("INVENTORY_SECRET", ""),
    "ntfy_secret": os.environ.get("NTFY_SECRET", ""),
    "inventory_file": os.environ.get("INVENTORY_FILE", ""),  # local testing
    "ntfy_topic": os.environ.get("NTFY_TOPIC", ""),  # local testing
    "ntfy_server": os.environ.get("NTFY_SERVER", "https://ntfy.sh"),
    "checkins": os.environ.get("CHECKINS", ""),  # "06:00,12:00 America/New_York"
    "bind": os.environ.get("BIND", ""),  # default: this peer's NetBird IP
    "port": int(os.environ.get("PORT", "8080")),
    "dry_run": os.environ.get("DRY_RUN", "") == "1",
}

RUN_GAP_S = 600  # between the two runs of a check-in
BOOT_WAIT_S = 900  # max wait for tablets to rejoin after the monitor starts
REBOOT_HOLD_S = 600  # a rebooted tablet's result is held as unknown this long
SCHEDULE_LEAD_MIN = 10  # first scheduled run is this many minutes early
WINDOW_BEFORE_MIN, WINDOW_AFTER_MIN = 40, 15  # same as the lease workflow
SCAN_FROM, SCAN_TO = 30000, 49999  # Wireless debugging port range seen so far

CHECK_LABELS = {
    "netbird": "NetBird online",
    "adb": "ADB reachable",
    "app_running": "App running",
    "app_front": "App in front",
    "printer": "Printer",
    "google": "Google account",
    "backend": "Backend connection",
    "live_label": "Live label",
}

STARTED = time.time()


def log(msg):
    print(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def run(args, timeout=30):
    """Runs a command (argument list, never a shell string). Returns (rc, stdout)."""
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.replace("\r", "")
    except (subprocess.TimeoutExpired, OSError) as e:
        return 1, str(e)


def aws_secret(secret_id):
    rc, out = run(["aws", "secretsmanager", "get-secret-value", "--region", CONFIG["region"],
                   "--secret-id", secret_id, "--query", "SecretString", "--output", "text"])
    if rc != 0:
        raise RuntimeError("cannot read secret " + secret_id)
    return out.strip()


def load_inventory():
    if CONFIG["inventory_file"]:
        with open(CONFIG["inventory_file"]) as f:
            data = json.load(f)
    else:
        data = json.loads(aws_secret(CONFIG["inventory_secret"]))
    tablets = []
    for t in data.get("tablets", []):
        tablets.append({
            "name": str(t["name"]),
            "site": str(t.get("site", "")),
            "host": str(t["host"]),
            "package": str(t.get("package", "com.plateraterestaurantsv2")),
            "printer": str(t.get("printer", "none")),
            "live_label": str(t.get("live_label", "Live")),
            "orders_pattern": str(t.get("orders_pattern", r"(\d+) orders?")),
            "event_log": str(t.get("event_log", "/sdcard/Documents/tablet-events.log")),
        })
    return tablets


def load_ntfy_topic():
    return CONFIG["ntfy_topic"] or aws_secret(CONFIG["ntfy_secret"])


def parse_checkins(spec):
    """'06:00,12:00 America/New_York' -> ([minutes after midnight], tz) or ([], None)."""
    m = re.fullmatch(r"(\d{1,2}:\d{2}(?:\s*,\s*\d{1,2}:\d{2})*)\s+(\S+)", spec.strip())
    if not m:
        return [], None
    tz = zoneinfo.ZoneInfo(m.group(2))
    times = []
    for t in m.group(1).split(","):
        h, mi = (int(x) for x in t.strip().split(":"))
        times.append(h * 60 + mi)
    return sorted(times), tz


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------

def netbird_status():
    rc, out = run(["netbird", "status", "--json"], timeout=15)
    if rc != 0:
        return {}, "", ""
    try:
        d = json.loads(out) or {}
    except ValueError:
        return {}, "", ""
    # Before login (LoginFailed, NeedsLogin) peers and details are null.
    details = (d.get("peers") or {}).get("details") or []
    peers = {(p.get("netbirdIp") or "").split("/")[0]: p.get("status", "") for p in details}
    return peers, (d.get("netbirdIp") or "").split("/")[0], d.get("fqdn") or ""


def wake_peer(host, port=5555, wait_s=15):
    """With NetBird lazy connections a peer stays "Idle" until traffic flows
    to it. Open a TCP connection to start the tunnel, then wait for the peer
    to show as Connected. Returns the last status seen."""
    import socket
    try:
        socket.create_connection((host, port), timeout=5).close()
    except OSError:
        pass  # the attempt alone starts the tunnel; the status below decides
    status = ""
    deadline = time.time() + wait_s
    while time.time() < deadline:
        status = netbird_status()[0].get(host, "")
        if status == "Connected":
            break
        time.sleep(2)
    return status


def adb(serial, *args, timeout=20):
    return run(["adb", "-s", serial, *args], timeout=timeout)


def adb_ok(host):
    run(["adb", "connect", host + ":5555"], timeout=10)
    rc, out = adb(host + ":5555", "shell", "echo", "ok", timeout=10)
    return rc == 0 and out.strip() == "ok"


async def _scan(host, lo, hi):
    sem = asyncio.Semaphore(500)
    found = []

    async def probe(p):
        async with sem:
            try:
                _, w = await asyncio.wait_for(asyncio.open_connection(host, p), 1.5)
                w.close()
                found.append(p)
            except Exception:
                pass

    await asyncio.gather(*(probe(p) for p in range(lo, hi + 1)))
    return sorted(found)


def ensure_adb(host):
    """ADB on host:5555, recovering through Wireless debugging after a reboot
    (same logic as tablet-adb.sh, without mDNS, which does not cross NetBird)."""
    if adb_ok(host):
        return True
    for port in asyncio.run(_scan(host, SCAN_FROM, SCAN_TO)):
        rc, out = run(["adb", "connect", "%s:%d" % (host, port)], timeout=10)
        if "connected to" not in out:
            continue
        log("%s: Wireless debugging on port %d, switching ADB to 5555" % (host, port))
        adb("%s:%d" % (host, port), "tcpip", "5555")
        run(["adb", "disconnect", "%s:%d" % (host, port)], timeout=10)
        for _ in range(10):
            time.sleep(2)
            if adb_ok(host):
                return True
    return False


def check_printer(serial, rule):
    kind, _, match = rule.partition(":")
    match = match.lower()
    if kind == "none":
        return None, "no printer rule"
    if kind == "bluetooth":
        _, out = adb(serial, "shell", "dumpsys", "bluetooth_manager")
        sec = out.split("Bonded devices:", 1)[-1].split("\n\n", 1)[0] if "Bonded devices:" in out else ""
        ok = match in sec.lower()
        return ok, ("paired" if ok else "no paired device matching '%s'" % match)
    if kind == "usb":
        _, out = adb(serial, "shell", "dumpsys", "usb")
        names = [n for n in re.findall(r"product_name=(.+)", out) if n.strip() != "null"]
        ok = any(match in n.lower() for n in names)
        return ok, ("attached" if ok else "no USB device matching '%s'" % match)
    if kind == "plugin":
        _, out = adb(serial, "shell", "dumpsys", "print")
        _, disabled = adb(serial, "shell", "settings", "get", "secure", "disabled_print_services")
        ok = ("package_name=" + match) in out.lower() and match not in disabled.lower()
        return ok, ("plugin enabled" if ok else "plugin '%s' missing or disabled" % match)
    return None, "unknown printer rule '%s'" % rule


def backend_connected(serial, package):
    _, pk = adb(serial, "shell", "dumpsys", "package", package)
    m = re.search(r"userId=(\d+)", pk)
    if not m:
        return False, "app UID not found"
    uid = m.group(1)
    _, tcp = adb(serial, "shell", "cat", "/proc/net/tcp", "/proc/net/tcp6")
    n = 0
    for line in tcp.splitlines()[1:]:
        f = line.split()
        # f[2] remote addr:port, f[3] state (01 = ESTABLISHED), f[7] uid
        if len(f) > 7 and f[7] == uid and f[3] == "01" and f[2].endswith(":01BB"):
            n += 1
    return n > 0, "%d connection(s) on 443" % n


def screen_texts(serial):
    path = "/sdcard/tablet-monitor-ui.xml"
    rc, _ = adb(serial, "shell", "uiautomator", "dump", path, timeout=30)
    if rc != 0:
        return None
    _, xml = adb(serial, "shell", "cat", path)
    adb(serial, "shell", "rm", "-f", path)
    texts = re.findall(r'(?:text|content-desc)="([^"]*)"', xml)
    return [t.strip() for t in texts if t.strip()]


def last_socket_log(serial):
    _, out = adb(serial, "logcat", "-d", "-t", "5000", "-s", "ReactNativeJS:I", timeout=20)
    hits = [l for l in out.splitlines() if "[VenueSocket] Connected" in l]
    return " ".join(hits[-1].split()[:2]) if hits else ""


def battery(serial):
    _, out = adb(serial, "shell", "dumpsys", "battery")
    f = dict(re.findall(r"^[ \t]*([\w ]+):[ \t]*(.+)$", out, re.M))
    info = {}
    if f.get("level", "").isdigit():
        info["battery_pct"] = int(f["level"])
    sources = [s for s in ("AC", "USB", "Wireless", "Dock") if f.get(s + " powered") == "true"]
    info["power"] = "+".join(sources) if sources else "battery only"
    if f.get("temperature", "").isdigit():
        info["battery_temp_c"] = int(f["temperature"]) / 10
    return info


def wifi(serial):
    _, out = adb(serial, "shell", "cmd", "wifi", "status")
    m = re.search(r'Wifi is connected to "([^"]*)"', out)
    if not m:
        return {"wifi": "not connected"}
    rssi = re.search(r"RSSI: (-?\d+)", out)
    return {"wifi": m.group(1), "wifi_rssi_dbm": int(rssi.group(1)) if rssi else None}


def events(serial, path):
    """Last 24 hours of the Automate event log (ADR-038 option 1), newest
    first. Lines are 'YYYY-MM-DD HH:MM:SS|kind|detail' in tablet local time."""
    rc, out = adb(serial, "shell", "tail", "-n", "300", path)
    if rc != 0:
        return []
    # The tablet logs local time; compare in the check-in zone (the
    # instance itself runs on UTC).
    tz = parse_checkins(CONFIG["checkins"])[1] or zoneinfo.ZoneInfo("UTC")
    cutoff = (datetime.datetime.now(tz) - datetime.timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S")
    rows = []
    for line in out.splitlines():
        parts = line.strip().split("|", 2)
        if len(parts) >= 2 and re.match(r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$", parts[0]) and parts[0] >= cutoff:
            rows.append({"at": parts[0], "kind": parts[1][:20], "detail": (parts[2] if len(parts) > 2 else "")[:80]})
    return rows[::-1][:30]


def check_tablet(t, peers):
    c, info = {}, {}
    host, pkg, serial = t["host"], t["package"], t["host"] + ":5555"
    status = peers.get(host, "")
    if status and status != "Connected":
        status = wake_peer(host)  # lazy connections: Idle until used
    c["netbird"] = (status == "Connected", status or "not a peer of this monitor")
    if not c["netbird"][0]:
        return c, info
    if not ensure_adb(host):
        c["adb"] = (False, "no ADB on 5555 and no Wireless debugging port answered")
        return c, info
    c["adb"] = (True, "5555")
    _, pid = adb(serial, "shell", "pidof", pkg)
    c["app_running"] = (bool(pid.strip()), ("pid " + pid.strip()) if pid.strip() else "no process")
    _, acts = adb(serial, "shell", "dumpsys", "activity", "activities")
    top = next((l.strip() for l in acts.splitlines() if "topResumedActivity=" in l), "")
    front = pkg in top
    top_pkg = re.search(r"\s([\w.]+)/", top)
    c["app_front"] = (front, "in front" if front else "front app: " + (top_pkg.group(1) if top_pkg else "unknown"))
    c["printer"] = check_printer(serial, t["printer"])
    _, acc = adb(serial, "shell", "dumpsys", "account")
    has_google = "type=com.google}" in acc
    c["google"] = (has_google, "signed in" if has_google else "no Google account")
    c["backend"] = backend_connected(serial, pkg)
    if front:
        texts = screen_texts(serial)
        if texts is None:
            c["live_label"] = (None, "screen read failed")
        else:
            live = t["live_label"] in texts
            c["live_label"] = (live, "shown" if live else "'%s' not on screen" % t["live_label"])
            m = next((re.search(t["orders_pattern"], x) for x in texts if re.search(t["orders_pattern"], x)), None)
            if m:
                info["orders"] = int(m.group(1))
    else:
        c["live_label"] = (None, "app not in front")
    info["socket_log"] = last_socket_log(serial)
    _, model = adb(serial, "shell", "getprop", "ro.product.model")
    info["model"] = model.strip()
    _, up = adb(serial, "shell", "cat", "/proc/uptime")
    try:
        info["uptime_s"] = int(float(up.split()[0]))
    except (ValueError, IndexError):
        pass
    _, boots = adb(serial, "shell", "settings", "get", "global", "boot_count")
    if boots.strip().isdigit():
        info["boot_count"] = int(boots.strip())
    info.update(battery(serial))
    info.update(wifi(serial))
    info["events"] = events(serial, t["event_log"])
    return c, info


# --------------------------------------------------------------------------
# State, check-ins and reports
# --------------------------------------------------------------------------

class Monitor:
    def __init__(self):
        self.lock = threading.Lock()
        self.tablets = load_inventory()
        self.ntfy_topic = load_ntfy_topic()
        self.checkin_times, self.tz = parse_checkins(CONFIG["checkins"])
        self.tz = self.tz or zoneinfo.ZoneInfo("UTC")
        self.results = {}  # name -> {"checks", "info", "at"}
        self.history = []  # last check-ins: {"at", "kind", "red": {name: [checks]}}
        self.checkin = None  # {"kind", "started", "phase"} while running
        self.held_until = {}
        self.last_reboot = {}
        self.last_order_seen = {}
        self.netbird_ip, self.fqdn = "", ""
        self._token, self._token_day = "", None

    # Page token, rotated daily (ADR-038 section 7).
    def token(self):
        today = datetime.datetime.now(self.tz).date()
        with self.lock:
            if self._token_day != today:
                self._token, self._token_day = secrets.token_urlsafe(32), today
            return self._token

    def run_once(self):
        peers, ip, fqdn = netbird_status()
        if ip:  # keep the last known address if the daemon blips
            self.netbird_ip, self.fqdn = ip, fqdn
        for t in self.tablets:
            try:
                checks, info = check_tablet(t, peers)
            except Exception as e:  # one broken tablet must not stop the others
                checks, info = {"adb": (None, "check error: %s" % e)}, {}
            now = time.time()
            with self.lock:
                prev = self.results.get(t["name"], {}).get("info", {})
                if "orders" in info and info["orders"] > prev.get("orders", 0):
                    self.last_order_seen[t["name"]] = now
                info["last_order_seen"] = self.last_order_seen.get(t["name"])
                self.results[t["name"]] = {"checks": checks, "info": info, "at": now}
            log("%s: %s" % (t["name"], ", ".join("%s=%s" % (k, v[0]) for k, v in checks.items())))
        return {n: dict(r["checks"]) for n, r in self.results.items()}

    def wait_for_tablets(self):
        deadline = STARTED + BOOT_WAIT_S
        while time.time() < deadline:
            peers, _, _ = netbird_status()
            waiting = [t["host"] for t in self.tablets if peers.get(t["host"]) != "Connected"]
            if not waiting:
                return
            for host in waiting:
                if peers.get(host):  # known peer, maybe Idle (lazy): wake it
                    wake_peer(host, wait_s=5)
            time.sleep(15)

    def start_checkin(self, kind):
        with self.lock:
            if self.checkin:
                return False
            self.checkin = {"kind": kind, "started": time.time(), "phase": "waiting for tablets"}
        threading.Thread(target=self._checkin, args=(kind,), daemon=True).start()
        return True

    def _phase(self, phase):
        with self.lock:
            self.checkin["phase"] = phase

    def _checkin(self, kind):
        try:
            self.wait_for_tablets()
            self._phase("run 1 of 2")
            first = self.run_once()
            self._phase("waiting 10 minutes for run 2")
            time.sleep(RUN_GAP_S)
            self._phase("run 2 of 2")
            second = self.run_once()
            red = {}
            now = time.time()
            for t in self.tablets:
                n = t["name"]
                if self.held_until.get(n, 0) > now:
                    continue
                failed = [k for k, v in second.get(n, {}).items()
                          if v[0] is False and first.get(n, {}).get(k, (None,))[0] is False]
                if failed:
                    red[n] = failed
            with self.lock:
                self.history.insert(0, {"at": now, "kind": kind, "red": red, "tablets": len(self.tablets)})
                del self.history[10:]
            log("check-in (%s) done: %d red" % (kind, len(red)))
            if red:
                self.report_red(red)
        except Exception as e:
            log("check-in failed: %s" % e)
        finally:
            with self.lock:
                self.checkin = None

    def report_red(self, red):
        names = {t["name"]: t for t in self.tablets}
        lines = []
        for n, failed in red.items():
            site = names[n]["site"]
            label = "%s (%s)" % (n, site) if site else n
            lines.append("%s: %s" % (label, ", ".join(CHECK_LABELS.get(k, k) for k in failed)))
        title = "Tablets: %d of %d red" % (len(red), len(self.tablets))
        self.ntfy(title, "\n".join(lines), priority="high", tags="rotating_light")

    def ntfy(self, title, message, priority="default", tags=""):
        if CONFIG["dry_run"]:
            log("ntfy (dry run): %s | %s" % (title, message.replace("\n", " / ")))
            return
        req = urllib.request.Request(
            "%s/%s" % (CONFIG["ntfy_server"], self.ntfy_topic), data=message.encode(), method="POST",
            headers={"Title": title, "Priority": priority, "Tags": tags,
                     **({"Click": "http://%s:%d/" % (self.netbird_ip, CONFIG["port"])} if self.netbird_ip else {})})
        try:
            urllib.request.urlopen(req, timeout=15).read()
        except Exception as e:
            log("ntfy failed: %s" % e)

    def reboot(self, name):
        t = next((x for x in self.tablets if x["name"] == name), None)
        if not t:
            return 404, "unknown tablet"
        now = time.time()
        with self.lock:
            if now - self.last_reboot.get(name, 0) < REBOOT_HOLD_S:
                return 429, "rebooted less than 10 minutes ago"
            self.last_reboot[name] = now
            self.held_until[name] = now + REBOOT_HOLD_S
        if not adb_ok(t["host"]):
            return 409, "ADB is not reachable"
        adb(t["host"] + ":5555", "reboot", timeout=15)
        log("reboot requested: %s" % name)
        self.ntfy("Tablet reboot: %s" % name, "Reboot requested from the status page.", tags="arrows_counterclockwise")
        return 200, "reboot sent"

    def snapshot(self):
        with self.lock:
            tablets = []
            for t in self.tablets:
                r = self.results.get(t["name"])
                checks = {k: {"ok": v[0], "detail": v[1]} for k, v in (r["checks"] if r else {}).items()}
                held = self.held_until.get(t["name"], 0) > time.time()
                vals = [v["ok"] for v in checks.values()]
                state = "unknown" if (not r or held) else ("red" if False in vals else "green")
                tablets.append({"name": t["name"], "site": t["site"], "host": t["host"], "state": state,
                                "held": held, "checks": checks, "info": r["info"] if r else {},
                                "at": r["at"] if r else None})
            return {"now": time.time(), "monitor": {"ip": self.netbird_ip, "fqdn": self.fqdn},
                    "checkin": dict(self.checkin) if self.checkin else None,
                    "next_checkin": self.next_scheduled_run(), "history": list(self.history),
                    "labels": CHECK_LABELS, "tablets": tablets}

    # Scheduling ------------------------------------------------------------

    def next_scheduled_run(self):
        """Epoch seconds of the next scheduled first run (check-in time minus 10 min)."""
        if not self.checkin_times:
            return None
        now = datetime.datetime.now(self.tz)
        best = None
        for day in (0, 1):
            base = (now + datetime.timedelta(days=day)).replace(hour=0, minute=0, second=0, microsecond=0)
            for m in self.checkin_times:
                at = base + datetime.timedelta(minutes=m - SCHEDULE_LEAD_MIN)
                if at > now and (best is None or at < best):
                    best = at
        return best.timestamp() if best else None

    def in_window_late(self):
        """True when now is inside a check-in window but past its first run time."""
        now = datetime.datetime.now(self.tz)
        minute = now.hour * 60 + now.minute
        for m in self.checkin_times:
            since_open = (minute - (m - WINDOW_BEFORE_MIN)) % 1440
            if since_open < WINDOW_BEFORE_MIN + WINDOW_AFTER_MIN:
                return since_open >= WINDOW_BEFORE_MIN - SCHEDULE_LEAD_MIN
        return None  # not in any window

    def scheduler(self):
        late = self.in_window_late()
        if late is None:
            self.start_checkin("on start")  # manual lease (ADR-038 section 5)
        elif late:
            self.start_checkin("scheduled (late start)")
        while True:
            nxt = self.next_scheduled_run()
            if nxt is None:
                return
            time.sleep(max(1, nxt - time.time()))
            self.start_checkin("scheduled")
            time.sleep(60)


# --------------------------------------------------------------------------
# Status page (ADR-038 section 7)
# --------------------------------------------------------------------------

PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tablet Monitor</title>
<style>
:root{--bg:#f6f7f9;--card:#fff;--fg:#1d2330;--muted:#667085;--line:#d0d5dd;--green:#12b76a;--red:#f04438;--gray:#98a2b3;--accent:#2e6be6}
@media (prefers-color-scheme:dark){:root{--bg:#0f1218;--card:#181c24;--fg:#e6e8ec;--muted:#98a2b3;--line:#2c3340;--accent:#6b9cff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,system-ui,sans-serif}
header{padding:16px;display:flex;flex-wrap:wrap;gap:8px 16px;align-items:baseline;border-bottom:1px solid var(--line)}
h1{font-size:18px;margin:0}.muted{color:var(--muted)}main{padding:16px;max-width:1100px;margin:auto}
#map{width:100%;max-width:640px;display:block;margin:0 auto 16px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px}
.card h2{font-size:16px;margin:0 0 2px;display:flex;align-items:center;gap:8px}
.dot{width:12px;height:12px;border-radius:50%;display:inline-block;flex:none}
.green{background:var(--green)}.red{background:var(--red)}.unknown{background:var(--gray)}
table{width:100%;border-collapse:collapse;margin:8px 0}td{padding:3px 0;vertical-align:top;border-top:1px solid var(--line)}
td:first-child{width:45%;color:var(--muted)}code{font:12px ui-monospace,monospace;word-break:break-all}
button{font:inherit;padding:6px 10px;border-radius:6px;border:1px solid var(--line);background:var(--card);color:var(--fg);cursor:pointer}
button.primary{background:var(--accent);border-color:var(--accent);color:#fff}button:disabled{opacity:.5;cursor:not-allowed}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:6px}.cmd{background:var(--bg);padding:6px;border-radius:6px;flex:1;min-width:0}
#msg{min-height:20px}
</style></head><body>
<header><h1>Tablet Monitor</h1><span class="muted" id="sub"></span><span style="flex:1"></span>
<button class="primary" id="checknow">Check now</button></header>
<main><div id="msg" class="muted"></div><svg id="map" viewBox="0 0 640 300" role="img" aria-label="Network map"></svg>
<div class="grid" id="cards"></div><h3>Recent check-ins</h3><div id="hist" class="muted"></div></main>
<script>
const TOKEN = "__TOKEN__";
const $ = s => document.querySelector(s);
const el = (tag, attrs = {}, text) => { const e = document.createElement(tag); for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v); if (text !== undefined) e.textContent = text; return e; };
const svg = (tag, attrs) => { const e = document.createElementNS("http://www.w3.org/2000/svg", tag); for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v); return e; };
const t = s => s ? new Date(s * 1000).toLocaleString() : "never";
const dur = s => { const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60); return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"; };
function copy(text, btn) {
  const ta = el("textarea"); ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
  document.body.appendChild(ta); ta.select(); document.execCommand("copy"); ta.remove();
  btn.textContent = "Copied"; setTimeout(() => btn.textContent = "Copy", 1500);
}
async function post(path, body) {
  const r = await fetch(path, {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({token: TOKEN, ...body})});
  if (r.status === 403) { location.reload(); return; }
  $("#msg").textContent = await r.text(); load();
}
function render(d) {
  const ci = d.checkin;
  $("#sub").textContent = (d.monitor.fqdn || d.monitor.ip || "") + (ci ? " · check-in running (" + ci.kind + "): " + ci.phase : " · next scheduled run: " + t(d.next_checkin));
  $("#checknow").disabled = !!ci;
  const m = $("#map"); m.replaceChildren();
  const cx = 320, cy = 150, n = d.tablets.length;
  d.tablets.forEach((tb, i) => {
    const a = (2 * Math.PI * i / Math.max(n, 1)) - Math.PI / 2, x = cx + 220 * Math.cos(a), y = cy + 110 * Math.sin(a);
    m.appendChild(svg("line", {x1: cx, y1: cy, x2: x, y2: y, stroke: "var(--line)", "stroke-width": 2}));
    m.appendChild(svg("circle", {cx: x, cy: y, r: 18, fill: "var(--" + (tb.state === "unknown" ? "gray" : tb.state) + ")"}));
    const lb = svg("text", {x: x, y: y + 34, "text-anchor": "middle", fill: "var(--fg)", "font-size": 13}); lb.textContent = tb.name; m.appendChild(lb);
  });
  m.appendChild(svg("rect", {x: cx - 55, y: cy - 18, width: 110, height: 36, rx: 8, fill: "var(--accent)"}));
  const mt = svg("text", {x: cx, y: cy + 5, "text-anchor": "middle", fill: "#fff", "font-size": 13}); mt.textContent = "monitor"; m.appendChild(mt);
  const cards = $("#cards"); cards.replaceChildren();
  for (const tb of d.tablets) {
    const c = el("div", {class: "card"}), h = el("h2");
    h.append(el("span", {class: "dot " + tb.state}), document.createTextNode(tb.name));
    c.append(h, el("div", {class: "muted"}, [tb.site, tb.host, tb.held ? "rebooting" : "", "checked " + t(tb.at)].filter(Boolean).join(" · ")));
    const tbl = el("table");
    for (const [k, label] of Object.entries(d.labels)) {
      const v = tb.checks[k]; const tr = el("tr");
      const mark = !v ? "–" : v.ok === true ? "✓" : v.ok === false ? "✗" : "–";
      tr.append(el("td", {}, label), el("td", {}, mark + " " + (v ? v.detail : "not checked")));
      tbl.append(tr);
    }
    const info = tb.info || {};
    // Uptime is as of the last check; the page adds the time since then.
    const up = info.uptime_s !== undefined && tb.at ? info.uptime_s + Math.max(0, d.now - tb.at) : undefined;
    const bat = info.battery_pct !== undefined ? info.battery_pct + "% · " + info.power + (info.battery_temp_c !== undefined ? " · " + info.battery_temp_c + " °C" : "") : undefined;
    const wf = info.wifi ? info.wifi + (info.wifi_rssi_dbm != null ? " · " + info.wifi_rssi_dbm + " dBm" : "") : undefined;
    for (const [label, val] of [["Uptime", up !== undefined ? dur(up) + " (since " + t(d.now - up) + ")" : undefined],
                                ["Boot count", info.boot_count], ["Battery", bat], ["Wi-Fi", wf], ["Active orders", info.orders], ["Last order seen", info.last_order_seen ? t(info.last_order_seen) : undefined], ["Last socket connect (log)", info.socket_log]]) {
      if (val === undefined || val === "") continue; const tr = el("tr"); tr.append(el("td", {}, label), el("td", {}, String(val))); tbl.append(tr);
    }
    c.append(tbl);
    if (info.events) {
      const ev = el("details"); ev.append(el("summary", {}, "Events, last 24 h (" + info.events.length + ")"));
      const et = el("table");
      for (const e of info.events) { const tr = el("tr"); tr.append(el("td", {}, e.at), el("td", {}, e.kind + (e.detail ? ": " + e.detail : ""))); et.append(tr); }
      if (!info.events.length) ev.append(el("div", {class: "muted"}, "No events logged by Automate."));
      ev.append(et); c.append(ev);
    }
    const online = tb.checks.netbird && tb.checks.netbird.ok;
    for (const cmd of ["TABLET_HOST=" + tb.host + " tablet-adb.sh scrcpy", "scrcpy -s " + tb.host + ":5555"]) {
      const row = el("div", {class: "row"}), b = el("button", {}, "Copy");
      b.disabled = !online; b.onclick = () => copy(cmd, b);
      row.append(el("code", {class: "cmd"}, cmd), b); c.append(row);
    }
    const row = el("div", {class: "row"}), rb = el("button", {}, "Reboot");
    rb.disabled = !(tb.checks.adb && tb.checks.adb.ok) || tb.held;
    rb.onclick = () => { if (confirm("Reboot " + tb.name + "?")) post("/api/reboot", {tablet: tb.name}); };
    row.append(rb, el("code", {class: "cmd"}, "adb -s " + tb.host + ":5555 reboot")); c.append(row);
    cards.append(c);
  }
  const hist = $("#hist"); hist.replaceChildren();
  if (!d.history.length) hist.textContent = "None yet.";
  for (const hh of d.history) {
    const red = Object.entries(hh.red);
    hist.append(el("div", {}, t(hh.at) + " · " + hh.kind + " · " + (red.length ? red.map(([n, f]) => n + ": " + f.map(k => d.labels[k] || k).join(", ")).join("; ") : "all " + hh.tablets + " green")));
  }
}
async function load() { try { render(await (await fetch("/status.json", {cache: "no-store"})).json()); } catch (e) { $("#msg").textContent = "Monitor unreachable"; } }
$("#checknow").onclick = () => post("/api/checknow", {});
load(); setInterval(load, 60000);
</script></body></html>"""


def make_handler(mon):
    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "tablet-monitor"

        def log_message(self, fmt, *args):
            log("http %s %s" % (self.address_string(), fmt % args))

        def allowed_hosts(self):
            port = CONFIG["port"]
            hosts = {h for h in (mon.netbird_ip, mon.fqdn, CONFIG["bind"]) if h}
            return hosts | {"%s:%d" % (h, port) for h in hosts}

        def send(self, code, body, ctype="text/plain; charset=utf-8"):
            data = body.encode() if isinstance(body, str) else body
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Content-Security-Policy", "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(data)

        def host_ok(self):
            # DNS rebinding guard: only our own NetBird IP or name.
            return self.headers.get("Host", "") in self.allowed_hosts()

        def do_GET(self):
            if not self.host_ok():
                return self.send(421, "wrong host")
            if self.path in ("/", "/index.html"):
                return self.send(200, PAGE.replace("__TOKEN__", mon.token()), "text/html; charset=utf-8")
            if self.path == "/status.json":
                return self.send(200, json.dumps(mon.snapshot()), "application/json")
            return self.send(404, "not found")

        def do_POST(self):
            if not self.host_ok():
                return self.send(421, "wrong host")
            # Cross-site guard: same-origin requests only, plus the page token.
            if self.headers.get("Origin", "") not in {"http://" + h for h in self.allowed_hosts()}:
                return self.send(403, "bad origin")
            if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                return self.send(415, "json only")
            try:
                body = json.loads(self.rfile.read(min(int(self.headers.get("Content-Length", "0")), 4096)) or b"{}")
            except ValueError:
                return self.send(400, "bad json")
            if not hmac.compare_digest(str(body.get("token", "")), mon.token()):
                return self.send(403, "bad token")
            if self.path == "/api/checknow":
                ok = mon.start_checkin("on request")
                return self.send(200 if ok else 409, "check-in started" if ok else "a check-in is already running")
            if self.path == "/api/reboot":
                code, msg = mon.reboot(str(body.get("tablet", "")))
                return self.send(code, msg)
            return self.send(404, "not found")

    return Handler


def serve(mon):
    while True:
        # Learn our own NetBird address and name before serving: the Host
        # and Origin checks compare against them. (Before this, they were
        # only set by the first check run, so the page answered 421 until
        # then; found on the first deploy, 2026-11-20.)
        _, ip, fqdn = netbird_status()
        if ip:
            mon.netbird_ip, mon.fqdn = ip, fqdn
        bind = CONFIG["bind"] or ip
        if bind:
            try:
                srv = http.server.ThreadingHTTPServer((bind, CONFIG["port"]), make_handler(mon))
                log("status page on http://%s:%d/" % (bind, CONFIG["port"]))
                srv.serve_forever()
            except OSError as e:
                log("cannot bind %s: %s" % (bind, e))
        time.sleep(10)  # NetBird not up yet: no address to bind


def main():
    mon = Monitor()
    if "--once" in sys.argv:
        mon.run_once()
        print(json.dumps(mon.snapshot(), indent=2, default=str))
        return
    threading.Thread(target=mon.scheduler, daemon=True).start()
    serve(mon)


if __name__ == "__main__":
    main()
