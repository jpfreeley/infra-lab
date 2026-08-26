#!/usr/bin/env python3
"""
mempalace_migrate_wing.py — one-time, wing-scoped copy of drawers from one
MemPalace instance to another, over the MCP API.

Why this exists (ADR-034, "MagNet Legal Instance"): backfilling the
MagNet Legal instance from the existing personal instance's `magnetlegal`
wing, once, before the team starts writing to the new instance directly.
Not a sync job — JP's decision was one-time backfill, then direct writes
going forward, so this is meant to be run once by hand, not scheduled.

Reuses the same pattern already proven twice this session (the 38-drawer
delta migration and mempalace_remote_backup.py): mempalace_list_drawers
to enumerate, mempalace_get_drawer for full verbatim content, then
mempalace_add_drawer against the destination — which is itself
content-hash idempotent, so rerunning this script is safe and just
no-ops on anything already copied.

Safe to run unfiltered-by-room for a single wing at this scale (unlike
the giant `enterprise` wing) — see scripts/mempalace_remote_backup.py's
own docstring for why an unfiltered scan doesn't always finish; a single
mid-sized wing's own record count is nowhere near what triggered that.

Usage:
    python3 scripts/mempalace_migrate_wing.py \
        --wing magnetlegal \
        --source-url https://mempalace.lintwiselabs.com/mcp \
        --source-token "$SOURCE_TOKEN" \
        --dest-url https://magnetlegal.mempalace.lintwiselabs.com/mcp \
        --dest-token "$DEST_TOKEN"
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request

LIST_PAGE_SIZE = 100
HTTP_TIMEOUT_S = 60
MAX_RETRIES = 3


def _rpc(url: str, token: str, method: str, params: dict, req_id: int = 1) -> dict:
    payload = json.dumps(
        {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
    ).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Authorization": f"Bearer {token}",
        },
    )
    last_error = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_S) as response:
                body = json.loads(response.read())
            if "error" in body:
                raise RuntimeError(f"MCP error: {body['error']}")
            return body["result"]
        except (urllib.error.URLError, TimeoutError, RuntimeError) as exc:
            last_error = exc
            if attempt < MAX_RETRIES:
                wait = 2 * attempt
                print(f"  retry {attempt}/{MAX_RETRIES} after error ({exc}); waiting {wait}s", file=sys.stderr)
                time.sleep(wait)
    raise RuntimeError(f"giving up after {MAX_RETRIES} attempts: {last_error}")


def tool_call(url: str, token: str, name: str, arguments: dict) -> dict:
    result = _rpc(url, token, "tools/call", {"name": name, "arguments": arguments})
    text = result["content"][0]["text"]
    return json.loads(text)


def list_wing_drawer_ids(url: str, token: str, wing: str) -> list:
    ids = []
    offset = 0
    while True:
        page = tool_call(
            url, token, "mempalace_list_drawers",
            {"wing": wing, "limit": LIST_PAGE_SIZE, "offset": offset},
        )
        drawers = page.get("drawers", [])
        if not drawers:
            break
        ids.extend(d["drawer_id"] for d in drawers)
        offset += len(drawers)
        if offset >= page.get("total", offset):
            break
    return ids


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wing", required=True, help="Wing to migrate, e.g. magnetlegal")
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--source-token", required=True)
    parser.add_argument("--dest-url", required=True)
    parser.add_argument("--dest-token", required=True)
    args = parser.parse_args()

    print(f"Listing '{args.wing}' drawers from {args.source_url} ...")
    ids = list_wing_drawer_ids(args.source_url, args.source_token, args.wing)
    print(f"{len(ids)} logical drawer(s) found.")

    results = {"ok": 0, "already_exists": 0, "error": 0}
    for i, drawer_id in enumerate(ids, 1):
        try:
            full = tool_call(args.source_url, args.source_token, "mempalace_get_drawer", {"drawer_id": drawer_id})
            add_args = {
                "wing": full["wing"],
                "room": full["room"],
                "content": full.get("content", ""),
            }
            md = full.get("metadata", {})
            if md.get("source_file"):
                add_args["source_file"] = md["source_file"]
            if md.get("added_by"):
                add_args["added_by"] = md["added_by"]

            dest_result = tool_call(args.dest_url, args.dest_token, "mempalace_add_drawer", add_args)
            if dest_result.get("reason") == "already_exists":
                results["already_exists"] += 1
            else:
                results["ok"] += 1
        except RuntimeError as exc:
            print(f"  WARNING: {drawer_id} failed: {exc}", file=sys.stderr)
            results["error"] += 1

        if i % 25 == 0 or i == len(ids):
            print(f"  {i}/{len(ids)}")

    print(f"\nDone. {results['ok']} new, {results['already_exists']} already present, {results['error']} error(s).")
    return 1 if results["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
