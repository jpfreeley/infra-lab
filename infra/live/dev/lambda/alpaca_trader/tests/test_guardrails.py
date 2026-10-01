"""Unit tests for the pure guardrail functions."""

from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from conftest import TEST_LIMITS

import guardrails

ET = ZoneInfo("America/New_York")


def params(**overrides):
    return guardrails.Params.from_dict({**TEST_LIMITS, **overrides})


def facts(**overrides):
    base = {
        "market_open": True,
        "now_et": datetime(2026, 9, 28, 10, 30, tzinfo=ET),
        "start_equity": 100000.0,
        "equity_now": 100000.0,
        "symbol": "XYZ",
        "held_symbols": set(),
        "pending_symbols": set(),
        "orders_run": 0,
        "orders_day": 0,
        "universe_reason": None,
        "last_price": 100.0,
        "entry": 100.0,
        "stop": 98.0,
    }
    return {**base, **overrides}


def test_params_valid():
    assert params().max_positions == 3


def test_params_missing_key_fails_closed():
    raw = dict(TEST_LIMITS)
    del raw["risk_pct"]
    with pytest.raises(guardrails.ConfigError):
        guardrails.Params.from_dict(raw)


def test_params_none_fails_closed():
    with pytest.raises(guardrails.ConfigError):
        guardrails.Params.from_dict(None)


@pytest.mark.parametrize(
    "key,value",
    [("risk_pct", 0.5), ("max_position_pct", 5), ("daily_loss_halt_pct", 0)],
)
def test_params_out_of_bounds_rejected(key, value):
    with pytest.raises(guardrails.ConfigError):
        params(**{key: value})


def test_params_bad_time_rejected():
    with pytest.raises(guardrails.ConfigError):
        params(last_entry_time="late")


def test_paper_check():
    good = {"account_number": "PA123"}
    assert guardrails.paper_check(guardrails.PAPER_BASE_URL, good) is None
    assert guardrails.paper_check("https://api.alpaca.markets", good)
    assert guardrails.paper_check(guardrails.PAPER_BASE_URL, {"account_number": "123"})


def test_daily_halt():
    p = params()
    assert guardrails.daily_halt(p, 100000, 94999)
    assert not guardrails.daily_halt(p, 100000, 96000)
    assert not guardrails.daily_halt(p, None, 1)


def test_size_bracket_risk_limited():
    sizing, err = guardrails.size_bracket(params(), 100000, 100.0, 98.0)
    assert err is None
    assert sizing["qty"] == 300  # min(1000/2 risk-based=500, 30000/100 notional=300)
    assert sizing["target"] == 106.0  # 3R from the test limits


def test_size_bracket_notional_capped():
    sizing, _ = guardrails.size_bracket(params(), 100000, 100.0, 99.9)
    assert sizing["notional"] <= 30000


def test_size_bracket_rejects_wide_stop():
    _, err = guardrails.size_bracket(params(), 100000, 100.0, 90.0)
    assert err


@pytest.mark.parametrize("entry,stop", [(100, 100), (100, 101), (0, 0), (100, -1)])
def test_size_bracket_rejects_bad_prices(entry, stop):
    _, err = guardrails.size_bracket(params(), 100000, entry, stop)
    assert err


def test_size_bracket_rejects_sub_share():
    _, err = guardrails.size_bracket(params(), 100, 500.0, 490.0)
    assert err


def test_stop_move_rules():
    assert guardrails.stop_move_reason(98, 97, 105)
    assert guardrails.stop_move_reason(98, 98, 105)
    assert guardrails.stop_move_reason(98, 106, 105)
    assert guardrails.stop_move_reason(98, 100, 105) is None


def test_evaluate_entry_ok():
    sizing, err = guardrails.evaluate_entry(params(), facts())
    assert err is None and sizing["qty"] > 0


@pytest.mark.parametrize(
    "override",
    [
        {"market_open": False},
        {"now_et": datetime(2026, 9, 28, 13, 0, tzinfo=ET)},
        {"equity_now": 90000.0},
        {"held_symbols": {"XYZ"}},
        {"pending_symbols": {"XYZ"}},
        {"held_symbols": {"A", "B"}, "pending_symbols": {"C"}},
        {"orders_run": 2},
        {"orders_day": 4},
        {"universe_reason": "price below minimum"},
        {"entry": 110.0},
        {"last_price": None},
        {"stop": 90.0},
    ],
)
def test_evaluate_entry_rejections(override):
    sizing, err = guardrails.evaluate_entry(params(), facts(**override))
    assert sizing is None and err


def asset(**overrides):
    base = {
        "symbol": "XYZ",
        "class": "us_equity",
        "status": "active",
        "tradable": True,
        "exchange": "NASDAQ",
        "name": "Example Corp Common Stock",
    }
    return {**base, **overrides}


def test_universe_ok():
    reason = guardrails.universe_reject_reason(params(), asset(), 50, 2e6, 1e8)
    assert reason is None


@pytest.mark.parametrize(
    "overrides,price,vol,dollar",
    [
        ({"symbol": "ABC.W"}, 50, 2e6, 1e8),
        ({"class": "crypto"}, 50, 2e6, 1e8),
        ({"tradable": False}, 50, 2e6, 1e8),
        ({"exchange": "OTC"}, 50, 2e6, 1e8),
        ({"name": "Example Acquisition Corp Warrants"}, 50, 2e6, 1e8),
        ({"name": "Direxion Daily Semiconductor Bear 3X Shares"}, 50, 2e6, 1e8),
        ({}, 5, 2e6, 1e8),
        ({}, 50, 1e5, 1e8),
        ({}, 50, 2e6, 1e6),
        ({}, None, 2e6, 1e8),
    ],
)
def test_universe_rejections(overrides, price, vol, dollar):
    reason = guardrails.universe_reject_reason(
        params(), asset(**overrides), price, vol, dollar
    )
    assert reason
