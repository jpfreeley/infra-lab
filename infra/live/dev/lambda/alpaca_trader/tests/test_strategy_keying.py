"""Tests for per-strategy keying of paths, credentials, config and labels."""

import json

import pytest
from conftest import TEST_LIMITS
from test_tools import FakeClient, FakeStore

import guardrails
import handler
import notify
from tools import RunContext, Toolbox


def test_default_strategy_keeps_original_layout():
    assert handler.strategy_root("a") == ""


def test_other_strategy_gets_its_own_root():
    assert handler.strategy_root("b") == "strategies/b/"


def test_default_credentials_come_from_the_original_env_var():
    env = {"ALPACA_SECRET_ARN": "arn-a", "ALPACA_SECRET_ARNS": '{"b": "arn-b"}'}
    assert handler.alpaca_secret_arn("a", env) == "arn-a"


def test_other_strategy_credentials_come_from_the_map():
    env = {"ALPACA_SECRET_ARN": "arn-a", "ALPACA_SECRET_ARNS": '{"b": "arn-b"}'}
    assert handler.alpaca_secret_arn("b", env) == "arn-b"


def test_unknown_strategy_credentials_fail_loudly():
    with pytest.raises(RuntimeError):
        handler.alpaca_secret_arn("c", {"ALPACA_SECRET_ARN": "arn-a"})


@pytest.mark.parametrize("bad", ["", "../x", "b/c", "1b", "B B", "x" * 17])
def test_strategy_id_pattern_rejects_bad_ids(bad):
    assert not handler.STRATEGY_ID.match(bad)


@pytest.mark.parametrize("good", ["a", "b", "growth2"])
def test_strategy_id_pattern_accepts_good_ids(good):
    assert handler.STRATEGY_ID.match(good)


def test_run_rejects_an_invalid_strategy_before_touching_aws():
    result = handler.handler({"slot": 1, "strategy": "../x"}, None)
    assert result["ok"] is False and "strategy" in result["error"]


def make_toolbox(strategy, config_root, slot=4):
    ctx = RunContext(
        slot=slot,
        day="2026-09-28",
        dry_run=True,
        ntfy_topic="t",
        strategy=strategy,
        config_root=config_root,
    )
    store = FakeStore()
    params = guardrails.Params.from_dict(TEST_LIMITS)
    return Toolbox(FakeClient(), store, params, ctx), store


def test_scan_universe_reads_the_strategys_own_universe():
    tools, store = make_toolbox("b", "strategies/b/config/")
    store.put_json("strategies/b/config/universe.json", {"symbols": ["UP", "BIG"]})
    store.put_json("config/universe.json", {"symbols": ["FLAT"]})
    result = json.loads(tools.call("scan_universe", {"min_change_pct": 1.5}))
    assert result["scanned"] == 4  # FakeClient returns its fixed set for batches
    assert "error" not in result


def test_scan_universe_does_not_fall_back_to_another_strategys_universe():
    tools, store = make_toolbox("b", "strategies/b/config/")
    store.put_json("config/universe.json", {"symbols": ["UP"]})
    assert "error" in json.loads(tools.call("scan_universe", {}))


def test_report_titles_carry_the_strategy_label(monkeypatch):
    sent = []
    monkeypatch.setattr(
        notify, "send", lambda topic, title, msg, **kw: sent.append(title) or True
    )
    tools, _ = make_toolbox("b", "strategies/b/config/")
    tools.call("send_report", {"title": "Midday", "message": "m"})
    assert sent == ["[DRY RUN] [B] Midday"]
