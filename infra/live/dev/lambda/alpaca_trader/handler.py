"""Scheduled paper trading runner.

Invoked by EventBridge Scheduler with {"slot": N} and an optional
"strategy" id. Each strategy has its own config, state, credentials and control
flag; the default strategy keeps the original S3 layout. Strategy text, prompts
and numeric limits are read at runtime from a private S3 config prefix, never
from this repository. Set {"dry_run": true} to simulate every write.
"""

import json
import logging
import os
import re
import time
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

import boto3

import agent
import guardrails
import notify
from alpaca_api import AlpacaClient, AlpacaError
from store import LockHeldError, Store
from tools import REPORT_SLOTS, RunContext, Toolbox

logger = logging.getLogger()
logger.setLevel(logging.INFO)
ET = ZoneInfo("America/New_York")
FLATTEN_SLOT = 5
FLATTEN_POLLS = 12
FLATTEN_POLL_SECONDS = 5
DEFAULT_STRATEGY = "a"
STRATEGY_ID = re.compile(r"^[a-z][a-z0-9]{0,15}$")

SYSTEM_PREAMBLE = (
    "You are one wakeup of a continuing paper trading agent on an Alpaca paper "
    "account. You are stateless: continuity comes only from the handoff and "
    "journal you are given. Use the tools to act. Limits are enforced in code, "
    "so a guardrail rejection is final for that request; adapt, do not retry the "
    "same call. Always finish by calling save_handoff, even on a no-trade run. "
    "Reports go out only through send_report in the report slots."
)


def _env(name):
    return os.environ[name]


def _secret(sm, arn):
    return sm.get_secret_value(SecretId=arn)["SecretString"].strip()


def strategy_root(strategy):
    """Return the S3 key root for a strategy. The default keeps the old layout."""
    return "" if strategy == DEFAULT_STRATEGY else f"strategies/{strategy}/"


def alpaca_secret_arn(strategy, environ):
    """Return the Alpaca credentials secret ARN for a strategy."""
    if strategy == DEFAULT_STRATEGY:
        return environ["ALPACA_SECRET_ARN"]
    arns = json.loads(environ.get("ALPACA_SECRET_ARNS") or "{}")
    if strategy not in arns:
        raise RuntimeError(f"no credentials configured for strategy {strategy}")
    return arns[strategy]


def _alert(topic, label, title, message):
    notify.send(topic, f"[{label}] {title}", message, priority=5, tags="rotating_light")


def _load_prompt_docs(store, slot, cfg):
    """Read the private strategy, guardrail text and prompts for this slot."""
    docs = []
    for name in ("STRATEGY.md", "GUARDRAILS.md", "prompts/COMMON.md"):
        key = f"{cfg}{name}"
        text = store.get_text(key, None, absolute=True)
        if text is None:
            raise RuntimeError(f"missing private config object {key}")
        docs.append(f"## {key}\n{text}")
    listing = store.s3.list_objects_v2(
        Bucket=store.bucket, Prefix=f"{cfg}prompts/slot-{slot}-"
    )
    slot_keys = [o["Key"] for o in listing.get("Contents", [])]
    if not slot_keys:
        raise RuntimeError(f"missing prompt for slot {slot}")
    docs.append(f"## {slot_keys[0]}\n{store.get_text(slot_keys[0], None, True)}")
    return "\n\n".join(docs)


def _flatten(client, toolbox, topic, dry_run):
    """Cancel all orders, close all positions, verify flat, alert on failure."""
    toolbox.journal("intent", action="flatten")
    if dry_run:
        toolbox.journal("result", action="flatten", simulated=True)
        return {"flat": True, "simulated": True}
    client.cancel_all_orders()
    client.close_all_positions()
    remaining = None
    for _ in range(FLATTEN_POLLS):
        time.sleep(FLATTEN_POLL_SECONDS)
        remaining = client.positions()
        if not remaining:
            toolbox.journal("result", action="flatten", flat=True)
            return {"flat": True}
        client.close_all_positions()
    symbols = [p["symbol"] for p in remaining or []]
    toolbox.journal("error", action="flatten", still_open=symbols)
    _alert(
        topic,
        toolbox.ctx.label,
        "FLATTEN FAILED",
        f"Positions still open after retries: {symbols}",
    )
    return {"flat": False, "still_open": symbols}


def _fallback_report(toolbox, topic, dry_run):
    """Send a templated report if the model did not."""
    acct = toolbox.get_account()
    positions = toolbox.get_positions()
    lines = [
        f"Equity {acct['equity']}, day P&L {acct['day_pnl']}",
        f"Open positions: {len(positions)}",
    ]
    lines += [f"{p['symbol']}: {p['unrealized_pl']}" for p in positions]
    prefix = "[DRY RUN] " if dry_run else ""
    title = f"{prefix}[{toolbox.ctx.label}] Paper trading report (auto)"
    notify.send(topic, title, "\n".join(lines))


def _run(event, context):
    slot = int(event.get("slot", 0))
    dry_run = bool(event.get("dry_run"))
    strategy = str(event.get("strategy") or DEFAULT_STRATEGY).lower()
    if not 1 <= slot <= 6:
        return {"ok": False, "error": "slot must be 1 to 6"}
    if not STRATEGY_ID.match(strategy):
        return {"ok": False, "error": "invalid strategy id"}
    label = strategy.upper()
    root = strategy_root(strategy)
    cfg = f"{root}config/"

    s3 = boto3.client("s3")
    sm = boto3.client("secretsmanager")
    bucket = _env("STATE_BUCKET")
    store = Store(s3, bucket, ("dryrun/" if dry_run else "") + root)
    now = datetime.now(ET)
    today = now.date().isoformat()
    topic = _secret(sm, _env("NTFY_SECRET_ARN"))

    if not dry_run:
        control = store.get_json(f"{root}control/enabled.json", {}, absolute=True) or {}
        in_window = (
            control.get("start_date", "9999") <= today <= control.get("end_date", "")
        )
        if not control.get("enabled") or not in_window:
            return {"ok": True, "skipped": "not enabled for today"}

    try:
        params = guardrails.Params.from_dict(
            store.get_json(f"{cfg}guardrails.json", None, absolute=True)
        )
    except guardrails.ConfigError as exc:
        _alert(topic, label, "Trading config invalid", str(exc))
        return {"ok": False, "error": str(exc)}

    keys = json.loads(_secret(sm, alpaca_secret_arn(strategy, os.environ)))
    client = AlpacaClient(keys["key_id"], keys["secret_key"])
    bad = guardrails.paper_check(client.trading_url, client.account())
    if bad:
        _alert(topic, label, "Paper check failed", bad)
        return {"ok": False, "error": bad}

    if not dry_run and not client.calendar(today):
        return {"ok": True, "skipped": "market closed today"}

    ctx = RunContext(
        slot=slot,
        day=today,
        dry_run=dry_run,
        ntfy_topic=topic,
        strategy=strategy,
        config_root=cfg,
    )
    toolbox = Toolbox(client, store, params, ctx)
    run_id = f"{getattr(context, 'aws_request_id', None) or uuid.uuid4()}"
    locked = False
    try:
        store.acquire_lock(run_id, slot)
        locked = True
    except LockHeldError as exc:
        _alert(topic, label, "Run skipped: lock held", f"slot {slot}: {exc}")
        if slot != FLATTEN_SLOT:
            return {"ok": False, "error": str(exc)}

    try:
        if slot == FLATTEN_SLOT:
            return {"ok": True, **_flatten(client, toolbox, topic, dry_run)}
        return _run_agent(store, toolbox, params, ctx, topic, slot, now, cfg)
    except Exception as exc:  # noqa: B902 - alert and stop cleanly, no retries
        logger.exception("run failed")
        toolbox.journal("error", error=f"{type(exc).__name__}: {exc}")
        _alert(
            topic,
            label,
            f"Trading run failed (slot {slot})",
            f"{type(exc).__name__}: {exc}",
        )
        return {"ok": False, "error": str(exc)}
    finally:
        if locked:
            store.release_lock(run_id)


def _run_agent(store, toolbox, params, ctx, topic, slot, now, cfg):
    system_text = SYSTEM_PREAMBLE + "\n\n" + _load_prompt_docs(store, slot, cfg)
    handoff = store.get_json("state/progress.json", {}) or {}
    tail = store.tail_lines(f"journal/{ctx.day}.jsonl", 30)
    dry_note = (
        "THIS IS A DRY RUN: orders and stop changes are simulated and state is "
        "isolated. Work as normal, and do not question why the run fired.\n"
        if ctx.dry_run
        else ""
    )
    user_text = (
        f"{dry_note}Date {ctx.day}, time {now.strftime('%H:%M')} ET. "
        f"You are running slot {slot} for strategy {ctx.label}.\n"
        f"Last handoff:\n{json.dumps(handoff, indent=2)}\n\n"
        "Today's journal so far (most recent lines):\n" + "\n".join(tail)
    )
    prices = (
        float(_env("MODEL_INPUT_USD_PER_MTOK")) / 1e6,
        float(_env("MODEL_OUTPUT_USD_PER_MTOK")) / 1e6,
    )
    bedrock = boto3.client("bedrock-runtime")
    result = agent.run_agent(
        bedrock, _env("MODEL_ID"), prices, system_text, user_text, toolbox, params
    )
    toolbox.journal("run_summary", **result)
    if result["stopped"] != "finished":
        _alert(topic, ctx.label, f"Run stopped early (slot {slot})", json.dumps(result))
    if slot in REPORT_SLOTS and not ctx.report_sent:
        _fallback_report(toolbox, topic, ctx.dry_run)
    return {"ok": True, **result}


def handler(event, context):
    """Lambda entry point."""
    try:
        return _run(event or {}, context)
    except (AlpacaError, KeyError, RuntimeError) as exc:
        logger.exception("startup failure")
        try:
            topic = _secret(boto3.client("secretsmanager"), _env("NTFY_SECRET_ARN"))
            label = str((event or {}).get("strategy") or DEFAULT_STRATEGY).upper()
            _alert(
                topic, label, "Trading startup failure", f"{type(exc).__name__}: {exc}"
            )
        except Exception:  # noqa: B902 - nothing more we can do
            logger.exception("alert also failed")
        return {"ok": False, "error": str(exc)}
