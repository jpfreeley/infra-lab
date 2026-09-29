"""Tests for guarded tool behavior using in-memory fakes."""

import json
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from conftest import TEST_LIMITS

import guardrails
from alpaca_api import AlpacaError
from tools import RunContext, Toolbox

ET = ZoneInfo("America/New_York")


class FakeStore:
    """In-memory stand-in for the S3 store."""

    def __init__(self):
        """Start empty."""
        self.files = {}

    def append_jsonl(self, key, entry):
        self.files.setdefault(key, []).append(entry)

    def get_text(self, key, default=None, absolute=False):
        rows = self.files.get(key)
        if rows is None:
            return default
        return "\n".join(json.dumps(r) for r in rows)

    def put_json(self, key, value, absolute=False):
        self.files[key] = value

    def get_json(self, key, default=None, absolute=False):
        return self.files.get(key, default)

    def put_text(self, key, text, absolute=False):
        self.files[key] = text


class FakeClient:
    """Minimal Alpaca client fake."""

    def __init__(self, market_open=True, orders=None, trade_day="2026-09-28"):
        """Configure market state and pre-existing orders."""
        self.market_open = market_open
        self.order_list = orders or []
        self.trade_day = trade_day
        self.scan_prices = {
            "UP": (103.0, 100.0),
            "FLAT": (100.5, 100.0),
            "PENNY": (5.5, 5.0),
            "BIG": (110.0, 100.0),
        }
        self.submitted = []
        self.replaced = []

    def account(self):
        return {"account_number": "PA1", "equity": "100000", "last_equity": "100000"}

    def positions(self):
        return []

    def clock(self):
        return {"is_open": self.market_open}

    def asset(self, symbol):
        return {
            "symbol": symbol,
            "class": "us_equity",
            "status": "active",
            "tradable": True,
            "exchange": "NASDAQ",
            "name": "Example Corp",
        }

    def bars(self, symbols, timeframe, start, end, limit, feed):
        result = {}
        for sym in symbols.split(","):
            prev_close = self.scan_prices.get(sym, (100.0, 100.0))[1]
            bar = {
                "t": "2026-09-25T04:00:00Z",
                "o": prev_close,
                "h": prev_close,
                "l": prev_close,
                "c": prev_close,
                "v": 1000000,
            }
            result[sym] = [bar]
        return {"bars": result}

    def snapshots(self, symbols, feed="iex"):
        trade_ts = f"{self.trade_day}T14:35:00Z"
        if "," not in symbols:
            return {symbols: {"latestTrade": {"p": 100.0, "t": trade_ts}}}
        snaps = {}
        for sym, (price, prev) in self.scan_prices.items():
            snaps[sym] = {
                "latestTrade": {"p": price, "t": trade_ts},
                "prevDailyBar": {"c": prev, "v": 1000000},
            }
        return snaps

    def submit_order(self, body):
        self.submitted.append(body)
        return {"id": "o1", "status": "accepted"}

    def replace_order(self, order_id, body):
        self.replaced.append((order_id, body))
        return {}

    def orders(self, after):
        return [dict(o) for o in self.order_list]


def make(client=None, dry_run=False):
    client = client or FakeClient()
    ctx = RunContext(slot=2, day="2026-09-28", dry_run=dry_run, ntfy_topic="t")
    ctx.now_et = lambda: datetime(2026, 9, 28, 10, 30, tzinfo=ET)
    store = FakeStore()
    params = guardrails.Params.from_dict(TEST_LIMITS)
    return Toolbox(client, store, params, ctx), client, store


def test_entry_success_builds_protected_bracket():
    tools, client, _ = make()
    result = json.loads(
        tools.call(
            "place_bracket_order", {"symbol": "xyz", "entry_limit": 100.0, "stop": 98.0}
        )
    )
    assert result["ok"]
    body = client.submitted[0]
    assert body["order_class"] == "bracket"
    assert body["stop_loss"]["stop_price"] == "98.0"
    assert body["take_profit"]["limit_price"] == "106.0"
    assert body["client_order_id"] == "20260928-s2-XYZ"


def test_entry_rejected_when_market_closed_sends_nothing():
    tools, client, store = make(FakeClient(market_open=False))
    result = json.loads(
        tools.call(
            "place_bracket_order", {"symbol": "XYZ", "entry_limit": 100.0, "stop": 98.0}
        )
    )
    assert not result["ok"]
    assert client.submitted == []
    assert store.files["journal/2026-09-28.jsonl"][0]["type"] == "rejected"


def test_entry_intent_journaled_before_submit():
    tools, client, store = make()
    tools.call(
        "place_bracket_order", {"symbol": "XYZ", "entry_limit": 100.0, "stop": 98.0}
    )
    kinds = [e["type"] for e in store.files["journal/2026-09-28.jsonl"]]
    assert kinds == ["intent", "result"]


def test_dry_run_sends_no_order():
    tools, client, _ = make(dry_run=True)
    result = json.loads(
        tools.call(
            "place_bracket_order", {"symbol": "XYZ", "entry_limit": 100.0, "stop": 98.0}
        )
    )
    assert result["simulated"] and client.submitted == []


def test_per_run_order_limit():
    tools, client, _ = make()
    for sym in ("AAA", "BBB", "CCC"):
        tools.call(
            "place_bracket_order", {"symbol": sym, "entry_limit": 100.0, "stop": 98.0}
        )
    assert len(client.submitted) == 2  # test limit is 2 per run


def test_submit_error_is_reported_not_raised():
    tools, client, _ = make()

    def boom(body):
        raise AlpacaError(422, "nope")

    client.submit_order = boom
    result = json.loads(
        tools.call(
            "place_bracket_order", {"symbol": "XYZ", "entry_limit": 100.0, "stop": 98.0}
        )
    )
    assert not result["ok"]


def test_duplicate_order_id_gives_clear_rejection():
    tools, client, _ = make()

    def dup(body):
        raise AlpacaError(422, '{"message":"client_order_id must be unique"}')

    client.submit_order = dup
    result = json.loads(
        tools.call(
            "place_bracket_order",
            {"symbol": "XYZ", "entry_limit": 100.0, "stop": 98.0},
        )
    )
    assert "already submitted" in result["rejected_by_guardrail"]


def test_scan_universe_filters_and_sorts():
    tools, _, store = make()
    store.put_json("config/universe.json", {"symbols": ["UP", "FLAT", "PENNY", "BIG"]})
    result = json.loads(tools.call("scan_universe", {"min_change_pct": 1.5}))
    assert [c["symbol"] for c in result["candidates"]] == ["BIG", "UP"]
    assert result["scanned"] == 4


def test_scan_universe_without_config_is_an_error():
    tools, _, _ = make()
    assert "error" in json.loads(tools.call("scan_universe", {}))


def test_scan_universe_ignores_a_stale_pre_open_trade():
    """Reject a trade printed before today (the pre-9:30 snapshot lag).

    However large the apparent move, a stale print must not be mistaken
    for a live pre-market price.
    """
    tools, client, store = make()
    store.put_json("config/universe.json", {"symbols": ["UP"]})
    client.snapshots = lambda symbols, feed="iex": {
        "UP": {"latestTrade": {"p": 500.0, "t": "2026-09-25T20:00:00Z"}}
    }
    result = json.loads(tools.call("scan_universe", {"min_change_pct": 1.0}))
    assert result["candidates"] == []


def test_scan_universe_uses_the_real_prior_close_not_the_snapshot_one():
    """Ignore the snapshot's prevDailyBar even when present and wrong.

    The true prior close must come from daily bars, not the (possibly
    stale) snapshot field.
    """
    tools, client, store = make()
    store.put_json("config/universe.json", {"symbols": ["UP"]})
    client.snapshots = lambda symbols, feed="iex": {
        "UP": {
            "latestTrade": {"p": 103.0, "t": "2026-09-28T14:35:00Z"},
            "prevDailyBar": {"c": 50.0, "v": 1},  # wrong on purpose
        }
    }
    result = json.loads(tools.call("scan_universe", {"min_change_pct": 1.0}))
    assert result["candidates"][0]["prev_close"] == 100.0  # from bars(), not 50.0


def stop_order(price):
    return {
        "id": "s1",
        "symbol": "XYZ",
        "side": "sell",
        "type": "stop",
        "status": "held",
        "stop_price": str(price),
        "legs": None,
    }


def test_stop_cannot_be_widened():
    client = FakeClient(orders=[stop_order(98.0)])
    tools, client, _ = make(client)
    result = json.loads(tools.call("move_stop_to", {"symbol": "XYZ", "new_stop": 97.0}))
    assert not result["ok"] and client.replaced == []


def test_stop_can_be_tightened():
    client = FakeClient(orders=[stop_order(98.0)])
    tools, client, _ = make(client)
    result = json.loads(tools.call("move_stop_to", {"symbol": "XYZ", "new_stop": 99.5}))
    assert result["ok"] and client.replaced[0][0] == "s1"


def test_unknown_tool_and_bad_args():
    tools, _, _ = make()
    assert "unknown tool" in tools.call("nope", {})
    assert "bad arguments" in tools.call("check_symbol", {})


def test_save_evidence_writes_a_dated_key():
    tools, _, store = make()
    result = json.loads(
        tools.call("save_evidence", {"filename": "fills.txt", "content": "a,b,c"})
    )
    assert result["ok"] and result["key"] == "state/evidence/2026-09-28-fills.txt"


def test_save_evidence_rejects_path_traversal():
    tools, _, _ = make()
    result = json.loads(
        tools.call("save_evidence", {"filename": "../secrets.txt", "content": "x"})
    )
    assert not result["ok"]


def test_save_evidence_rejects_a_slash_in_the_name():
    tools, _, _ = make()
    result = json.loads(
        tools.call("save_evidence", {"filename": "a/b.txt", "content": "x"})
    )
    assert not result["ok"]


def test_save_evidence_rejects_oversized_content():
    tools, _, _ = make()
    result = json.loads(
        tools.call("save_evidence", {"filename": "big.txt", "content": "x" * 20001})
    )
    assert not result["ok"]


def test_save_evidence_dry_run_does_not_write():
    tools, _, store = make(dry_run=True)
    result = json.loads(
        tools.call("save_evidence", {"filename": "fills.txt", "content": "a"})
    )
    assert result["simulated"]


def test_reports_only_in_report_slots():
    tools, _, _ = make()
    result = json.loads(tools.call("send_report", {"title": "t", "message": "m"}))
    assert not result["ok"]


@pytest.mark.parametrize("bad", [None, "x", []])
def test_handoff_must_be_object(bad):
    tools, _, _ = make()
    assert not json.loads(tools.call("save_handoff", {"handoff": bad}))["ok"]
