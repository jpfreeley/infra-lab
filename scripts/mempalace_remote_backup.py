#!/usr/bin/env python3
"""
mempalace_remote_backup.py — backend-agnostic backup of the shared MemPalace
server's drawers, via its own MCP API.

Why this exists (ADR-034, docs/adr/034-shared-mempalace-server.md): the
existing mp_sync.py backup job reads Chroma's native collections API
directly, which only works against a local, Chroma-backed palace. The
shared remote server runs on qdrant, which mp_sync has no code path for at
all — pointing it at remote would just fail. This script sidesteps the
backend entirely by walking the same MCP tool surface any client uses
(mempalace_list_drawers + mempalace_get_drawer).

KNOWN LIMITATION, READ BEFORE CHANGING --exclude-wing:
`mempalace_list_drawers` has a real scaling ceiling on a qdrant-backed
palace — filed upstream at https://github.com/MemPalace/mempalace/issues/2363.
It does a full linear scan of whatever it's asked to match (the *whole*
collection if no wing/room filter is given, or the wing/room's whole
matching set if one is) before slicing out the requested page, with no
offset/limit pushed down to the database. Measured directly against this
palace: a single page from a 15,197-record room took 28.4 seconds, and an
unfiltered call against the ~35k-record collection didn't complete inside
the load balancer's 60s timeout at all. Because of this, this script:

  - always calls list_drawers with a `wing` filter (never unfiltered),
    which keeps each call scoped to one wing's own record count, and
  - takes --exclude-wing / MEMPALACE_BACKUP_EXCLUDE_WINGS from the
    caller rather than hardcoding one here (this is a public repo — a
    palace's wing names are personal information, not infra config),
    for whichever wing(s) are too large to finish a wing-scoped scan
    inside the timeout. Check mempalace_status for each wing's size
    before excluding or including one.

This means a run with wings excluded does NOT produce a complete
backup of the palace — only of whatever wasn't excluded. Don't drop a
wing from --exclude-wing until you've confirmed a wing-scoped scan of
it will actually finish (see the timing above) — the upstream issue
would need fixing first, or a different transport built (e.g. talking
to qdrant's own scroll API directly, bypassing this MCP endpoint).

Usage:
    MEMPALACE_URL=https://mempalace.lintwiselabs.com/mcp \
    MEMPALACE_TOKEN=... \
    python3 scripts/mempalace_remote_backup.py \
        --out-dir /path/to/mempalace-sync/export-mempalace-remote \
        --exclude-wing <wing-name> [--exclude-wing <another-wing>]

Writes (schema matches mp_sync.py's own export format, so this is a
drop-in-compatible backup):
    <out-dir>/snapshot/collections/drawers.jsonl.gz
    <out-dir>/snapshot/manifest.json
"""

import argparse
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

LIST_PAGE_SIZE = 100  # max the API allows
HTTP_TIMEOUT_S = 90  # generous margin over the ALB's own 60s idle timeout
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


def get_wings(url: str, token: str) -> dict:
    status = tool_call(url, token, "mempalace_status", {})
    return status.get("wings", {})


def list_wing_drawer_ids(url: str, token: str, wing: str) -> list:
    """Page through one wing via a wing-scoped (never unfiltered) list_drawers call."""
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


def fetch_full_drawer(url: str, token: str, drawer_id: str) -> dict:
    obj = tool_call(url, token, "mempalace_get_drawer", {"drawer_id": drawer_id})
    return {
        "id": drawer_id,
        "document": obj.get("content", ""),
        "metadata": obj.get("metadata", {}),
    }


def _env_exclude_wings() -> list:
    raw = os.environ.get("MEMPALACE_BACKUP_EXCLUDE_WINGS", "")
    return [w.strip() for w in raw.split(",") if w.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out-dir", required=True, help="Destination snapshot root, e.g. .../mempalace-sync/export-mempalace-remote")
    parser.add_argument(
        "--exclude-wing", action="append", default=None,
        help=(
            "Wing to skip (repeatable). Falls back to "
            "MEMPALACE_BACKUP_EXCLUDE_WINGS (comma-separated) if not "
            "given; no built-in default — see the module docstring."
        ),
    )
    parser.add_argument("--url", default=os.environ.get("MEMPALACE_URL", "https://mempalace.lintwiselabs.com/mcp"))
    parser.add_argument("--token", default=os.environ.get("MEMPALACE_TOKEN"))
    args = parser.parse_args()

    if not args.token:
        print("ERROR: set MEMPALACE_TOKEN or pass --token", file=sys.stderr)
        return 1

    exclude = set(args.exclude_wing) if args.exclude_wing else set(_env_exclude_wings())
    if not exclude:
        print(
            "WARNING: no --exclude-wing / MEMPALACE_BACKUP_EXCLUDE_WINGS "
            "given — every wing gets scanned. Check mempalace_status "
            "first; a large wing can take a long time or hit the "
            "list_drawers scaling ceiling "
            "(github.com/MemPalace/mempalace/issues/2363).",
            file=sys.stderr,
        )

    print(f"Fetching wing list from {args.url} ...")
    wings = get_wings(args.url, args.token)
    included_wings = sorted(w for w in wings if w not in exclude)
    skipped_wings = sorted(w for w in wings if w in exclude)
    print(f"Wings included ({len(included_wings)}): {included_wings}")
    print(f"Wings skipped  ({len(skipped_wings)}): {skipped_wings} (chunk counts: "
          f"{ {w: wings[w] for w in skipped_wings} })")

    all_records = []
    warnings = []
    for wing in included_wings:
        print(f"\n[{wing}] listing drawer IDs...")
        try:
            ids = list_wing_drawer_ids(args.url, args.token, wing)
        except RuntimeError as exc:
            msg = f"wing '{wing}' failed to list, skipping it: {exc}"
            print(f"  WARNING: {msg}", file=sys.stderr)
            warnings.append(msg)
            continue
        print(f"[{wing}] {len(ids)} logical drawer(s), fetching full content...")
        for i, drawer_id in enumerate(ids, 1):
            try:
                all_records.append(fetch_full_drawer(args.url, args.token, drawer_id))
            except RuntimeError as exc:
                msg = f"drawer '{drawer_id}' (wing '{wing}') failed to fetch, skipping it: {exc}"
                print(f"  WARNING: {msg}", file=sys.stderr)
                warnings.append(msg)
            if i % 25 == 0 or i == len(ids):
                print(f"  {i}/{len(ids)}")

    collections_dir = os.path.join(args.out_dir, "snapshot", "collections")
    os.makedirs(collections_dir, exist_ok=True)
    drawers_path = os.path.join(collections_dir, "drawers.jsonl.gz")
    with gzip.open(drawers_path, "wt", encoding="utf-8") as f:
        for record in all_records:
            f.write(json.dumps(record) + "\n")

    manifest = {
        "format_version": 3,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source": "mempalace-remote (qdrant)",
        "backup_method": "mcp_list_drawers_per_wing",
        "collections": {
            "drawers": {
                "name": "mempalace_drawers",
                "records": len(all_records),
                "file": "collections/drawers.jsonl.gz",
            }
        },
        "wings_included": included_wings,
        "wings_skipped": skipped_wings,
        "known_gap": (
            "closets collection and typed knowledge-graph facts are not "
            "captured — neither is exposed via any MCP tool. "
            "wings_skipped are not backed up by this run at all — see "
            "the module docstring and "
            "https://github.com/MemPalace/mempalace/issues/2363."
        ),
        "export_warnings": warnings,
    }
    manifest_path = os.path.join(args.out_dir, "snapshot", "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    print(f"\nWrote {len(all_records)} record(s) to {drawers_path}")
    print(f"Wrote manifest to {manifest_path}")
    if warnings:
        print(f"{len(warnings)} warning(s) — see manifest.json export_warnings", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
