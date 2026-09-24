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


class FakeClient:
    """Minimal Alpaca client fake."""

    def __init__(self, market_open=True, orders=None):
        """Configure market state and pre-existing orders."""
        self.market_open = market_open
        self.order_list = orders or []
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
        bar = {
            "t": "2026-09-25T04:00:00Z",
            "o": 99,
            "h": 101,
            "l": 98,
            "c": 100,
            "v": 2e6,
        }
        return {"bars": {symbols: [bar] * 20}}

    def snapshots(self, symbols):
        return {symbols: {"latestTrade": {"p": 100.0}}}

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


def test_reports_only_in_report_slots():
    tools, _, _ = make()
    result = json.loads(tools.call("send_report", {"title": "t", "message": "m"}))
    assert not result["ok"]


@pytest.mark.parametrize("bad", [None, "x", []])
def test_handoff_must_be_object(bad):
    tools, _, _ = make()
    assert not json.loads(tools.call("save_handoff", {"handoff": bad}))["ok"]
