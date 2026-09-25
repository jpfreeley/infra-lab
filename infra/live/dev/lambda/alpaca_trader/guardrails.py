"""Hard trading guardrails: pure functions, no I/O.

Numeric limits are NOT hardcoded here. They are loaded from a private config
object at runtime (see Params.from_dict) and this module fails closed when the
config is missing or a value is outside the generic sanity bounds below.
"""

import math
import re
from dataclasses import dataclass
from datetime import time

PAPER_BASE_URL = "https://paper-api.alpaca.markets"
PAPER_ACCOUNT_PREFIX = "PA"

# Generic sanity bounds on config values. They exist only to stop a typo in
# the private config from removing a safety limit.
_BOUNDS = {
    "max_positions": (1, 20),
    "max_position_pct": (0.001, 0.5),
    "risk_pct": (0.0001, 0.02),
    "max_stop_pct": (0.001, 0.10),
    "reward_r": (0.5, 10.0),
    "daily_loss_halt_pct": (0.001, 0.10),
    "min_price": (1.0, 10000.0),
    "min_avg_volume": (1, 10**10),
    "min_avg_dollar_volume": (1, 10**13),
    "max_entry_deviation_pct": (0.0001, 0.05),
    "max_orders_per_run": (1, 50),
    "max_orders_per_day": (1, 500),
    "max_turns": (1, 100),
    "max_run_cost_usd": (0.01, 25.0),
}

_ACTIVE_ORDER_STATUSES = frozenset(
    {
        "new",
        "accepted",
        "held",
        "partially_filled",
        "pending_new",
        "pending_replace",
        "accepted_for_bidding",
    }
)

_EXCLUDED_NAME_PATTERN = re.compile(
    r"\b(WARRANTS?|RIGHTS?|UNITS?|PREFERRED|NOTES?|2X|3X|ULTRA|ULTRAPRO|"
    r"ULTRASHORT|INVERSE|LEVERAGED|BULL|BEAR)\b",
    re.IGNORECASE,
)
_SYMBOL_PATTERN = re.compile(r"^[A-Z]{1,5}$")


class ConfigError(Exception):
    """Raised when the private guardrail config is missing or invalid."""


@dataclass(frozen=True)
class Params:
    """Validated guardrail limits."""

    max_positions: int
    max_position_pct: float
    risk_pct: float
    max_stop_pct: float
    reward_r: float
    daily_loss_halt_pct: float
    last_entry_time: time
    min_price: float
    min_avg_volume: float
    min_avg_dollar_volume: float
    max_entry_deviation_pct: float
    max_orders_per_run: int
    max_orders_per_day: int
    max_turns: int
    max_run_cost_usd: float

    @classmethod
    def from_dict(cls, raw):
        """Validate a config dict and build Params, or raise ConfigError."""
        if not isinstance(raw, dict):
            raise ConfigError("guardrail config is not an object")
        values = {}
        for key, (low, high) in _BOUNDS.items():
            if key not in raw:
                raise ConfigError(f"guardrail config missing {key}")
            value = raw[key]
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ConfigError(f"guardrail {key} must be a number")
            if not low <= value <= high:
                raise ConfigError(f"guardrail {key} outside sane bounds")
            values[key] = value
        try:
            hour, minute = str(raw["last_entry_time"]).split(":")
            values["last_entry_time"] = time(int(hour), int(minute))
        except (KeyError, ValueError) as exc:
            raise ConfigError("guardrail last_entry_time must be HH:MM") from exc
        return cls(**values)


def paper_check(base_url, account):
    """Return a reason string if this is not the paper account, else None."""
    if base_url.rstrip("/") != PAPER_BASE_URL:
        return "trading base URL is not the paper endpoint"
    number = str(account.get("account_number", ""))
    if not number.startswith(PAPER_ACCOUNT_PREFIX):
        return "account number does not look like a paper account"
    return None


def daily_halt(params, start_equity, equity_now):
    """Return True when the day's loss limit has been hit."""
    if not start_equity:
        return False
    return equity_now <= start_equity * (1 - params.daily_loss_halt_pct)


def is_active_status(status):
    """Return True for statuses that are live or pending orders."""
    return str(status) in _ACTIVE_ORDER_STATUSES


def universe_reject_reason(params, asset, price, avg_volume, avg_dollar_volume):
    """Return why a symbol is not tradable under the universe rules, or None."""
    symbol = str(asset.get("symbol", ""))
    if not _SYMBOL_PATTERN.match(symbol):
        return "symbol format not allowed"
    if asset.get("class") != "us_equity":
        return "not a US equity or ETF"
    if asset.get("status") != "active" or not asset.get("tradable"):
        return "not active and tradable"
    if str(asset.get("exchange", "")).upper() == "OTC":
        return "OTC symbol"
    if _EXCLUDED_NAME_PATTERN.search(str(asset.get("name", ""))):
        return "excluded security type by name"
    if price is None or price < params.min_price:
        return "price below minimum"
    if avg_volume is None or avg_volume < params.min_avg_volume:
        return "average volume below minimum"
    if avg_dollar_volume is None or avg_dollar_volume < params.min_avg_dollar_volume:
        return "average dollar volume below minimum"
    return None


def size_bracket(params, start_equity, entry, stop):
    """Compute position size and target. Returns (sizing dict, error string)."""
    if not (entry > 0 and stop > 0 and stop < entry):
        return None, "stop must be positive and below the entry price"
    stop_pct = (entry - stop) / entry
    if stop_pct > params.max_stop_pct:
        return None, "stop is wider than the allowed maximum"
    per_share_risk = entry - stop
    by_risk = math.floor(start_equity * params.risk_pct / per_share_risk)
    by_notional = math.floor(start_equity * params.max_position_pct / entry)
    qty = min(by_risk, by_notional)
    if qty < 1:
        return None, "computed size is less than one share"
    target = round(entry + params.reward_r * per_share_risk, 2)
    return {
        "qty": qty,
        "entry": round(entry, 2),
        "stop": round(stop, 2),
        "target": target,
        "risk_dollars": round(qty * per_share_risk, 2),
        "notional": round(qty * entry, 2),
    }, None


def stop_move_reason(current_stop, new_stop, last_price):
    """Return why a stop move is not allowed for a long position, or None."""
    if new_stop <= current_stop:
        return "stops may only be tightened, never widened"
    if new_stop >= last_price:
        return "new stop must be below the current price"
    return None


def evaluate_entry(params, facts):
    """Check every entry rule. Returns (sizing dict, None) or (None, reason)."""
    if not facts["market_open"]:
        return None, "market is not open"
    if facts["now_et"].time() >= params.last_entry_time:
        return None, "past the last allowed entry time"
    if daily_halt(params, facts["start_equity"], facts["equity_now"]):
        return None, "daily loss limit reached"
    symbol = facts["symbol"]
    if symbol in facts["held_symbols"] or symbol in facts["pending_symbols"]:
        return None, "already holding or working an order in this symbol"
    occupied = set(facts["held_symbols"]) | set(facts["pending_symbols"])
    if len(occupied) >= params.max_positions:
        return None, "maximum open positions reached"
    if facts["orders_run"] >= params.max_orders_per_run:
        return None, "per-run order limit reached"
    if facts["orders_day"] >= params.max_orders_per_day:
        return None, "per-day order limit reached"
    if facts["universe_reason"]:
        return None, facts["universe_reason"]
    last = facts["last_price"]
    if not last or abs(facts["entry"] - last) / last > params.max_entry_deviation_pct:
        return None, "entry price too far from the current price"
    return size_bracket(params, facts["start_equity"], facts["entry"], facts["stop"])
