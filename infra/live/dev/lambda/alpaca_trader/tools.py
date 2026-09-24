"""Tools exposed to the model. Every write path is guarded by guardrails.py."""

import json
import logging
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from statistics import mean
from zoneinfo import ZoneInfo

import guardrails
import notify
from alpaca_api import AlpacaError
from store import now_iso

logger = logging.getLogger()
ET = ZoneInfo("America/New_York")
MAX_RESULT_CHARS = 24000
TIMEFRAMES = {"1Min", "5Min", "15Min", "30Min", "1Hour", "1Day"}
REPORT_SLOTS = {4, 6}


@dataclass
class RunContext:
    """Mutable facts about the current run."""

    slot: int
    day: str
    dry_run: bool
    ntfy_topic: str
    orders_run: int = 0
    report_sent: bool = False

    def now_et(self):
        """Return the current time in New York."""
        return datetime.now(ET)


def _f(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _spec(name, description, properties=None, required=None):
    schema = {"type": "object", "properties": properties or {}}
    if required:
        schema["required"] = required
    return {
        "toolSpec": {
            "name": name,
            "description": description,
            "inputSchema": {"json": schema},
        }
    }


class Toolbox:
    """Model-callable tools bound to one run."""

    def __init__(self, client, store, params, ctx):
        """Bind the toolbox to a client, state store, limits and run context."""
        self.client = client
        self.store = store
        self.params = params
        self.ctx = ctx

    # Journal ---------------------------------------------------------------

    def journal(self, kind, **fields):
        """Append an entry to today's journal."""
        entry = {"ts": now_iso(), "slot": self.ctx.slot, "type": kind, **fields}
        self.store.append_jsonl(f"journal/{self.ctx.day}.jsonl", entry)

    def _orders_today(self):
        text = self.store.get_text(f"journal/{self.ctx.day}.jsonl", "") or ""
        return sum(1 for line in text.splitlines() if '"type": "intent"' in line)

    # Reads -----------------------------------------------------------------

    def get_account(self):
        """Return equity, day P&L and halt status."""
        acct = self.client.account()
        equity, last = _f(acct.get("equity")), _f(acct.get("last_equity"))
        halted = guardrails.daily_halt(self.params, last, equity or 0)
        return {
            "equity": equity,
            "start_of_day_equity": last,
            "day_pnl": round(equity - last, 2) if equity and last else None,
            "cash": _f(acct.get("cash")),
            "buying_power": _f(acct.get("buying_power")),
            "daily_loss_limit_hit": halted,
        }

    def get_positions(self):
        """Return open positions."""
        keep = (
            "symbol",
            "qty",
            "avg_entry_price",
            "current_price",
            "unrealized_pl",
            "unrealized_plpc",
            "market_value",
        )
        return [{k: p.get(k) for k in keep} for p in self.client.positions()]

    def _active_orders(self):
        after = f"{self.ctx.day}T00:00:00Z"
        flat = []
        for order in self.client.orders(after):
            legs = order.pop("legs", None) or []
            flat.append(order)
            for leg in legs:
                leg["parent_order_id"] = order.get("id")
                flat.append(leg)
        keep = (
            "id",
            "symbol",
            "side",
            "type",
            "status",
            "qty",
            "limit_price",
            "stop_price",
            "parent_order_id",
            "client_order_id",
        )
        return [
            {k: o.get(k) for k in keep}
            for o in flat
            if guardrails.is_active_status(o.get("status"))
        ]

    def get_open_orders(self):
        """Return live and pending orders, including bracket legs."""
        return self._active_orders()

    def get_movers(self, top=25):
        """Return market movers at or above the minimum price."""
        data = self.client.movers(min(int(top), 50))
        floor = self.params.min_price
        return {
            side: [m for m in data.get(side, []) if (m.get("price") or 0) >= floor]
            for side in ("gainers", "losers")
        }

    def get_most_actives(self, top=30):
        """Return the most active symbols by volume."""
        data = self.client.most_actives(min(int(top), 50))
        return [row.get("symbol") for row in data.get("most_actives", [])]

    def get_snapshots(self, symbols):
        """Return compact snapshots for comma-separated symbols."""
        raw = self.client.snapshots(symbols.upper().replace(" ", ""))
        out = {}
        for sym, snap in raw.items():
            prev = (snap.get("prevDailyBar") or {}).get("c")
            daily = snap.get("dailyBar") or {}
            price = (snap.get("latestTrade") or {}).get("p") or daily.get("c")
            out[sym] = {
                "price": price,
                "prev_close": prev,
                "change_pct": (
                    round((price / prev - 1) * 100, 2) if price and prev else None
                ),
                "day_open": daily.get("o"),
                "day_high": daily.get("h"),
                "day_low": daily.get("l"),
                "day_volume": daily.get("v"),
                "minute_close": (snap.get("minuteBar") or {}).get("c"),
            }
        return out

    def get_bars(self, symbols, timeframe="5Min", start=None, limit=200):
        """Return OHLCV bars. Intraday uses IEX, daily uses prior-day SIP."""
        if timeframe not in TIMEFRAMES:
            return {"error": f"timeframe must be one of {sorted(TIMEFRAMES)}"}
        limit = max(1, min(int(limit), 500))
        today = date.fromisoformat(self.ctx.day)
        if timeframe == "1Day":
            feed = "sip"
            end = f"{(today - timedelta(days=1)).isoformat()}T23:59:59Z"
            start = start or f"{(today - timedelta(days=45)).isoformat()}T00:00:00Z"
        else:
            feed = "iex"
            end = None
            opening = datetime.combine(today, time(9, 30), ET)
            start = start or opening.astimezone(timezone.utc).isoformat()
        raw = self.client.bars(
            symbols.upper().replace(" ", ""), timeframe, start, end, 10000, feed
        )
        out = {}
        for sym, bars in (raw.get("bars") or {}).items():
            rows = [[b["t"], b["o"], b["h"], b["l"], b["c"], b["v"]] for b in bars]
            out[sym] = rows[-limit:]
        return {"columns": ["t", "o", "h", "l", "c", "v"], "bars": out}

    def get_news(self, symbols, limit=5):
        """Return recent headlines for comma-separated symbols."""
        start = f"{(date.fromisoformat(self.ctx.day) - timedelta(days=2)).isoformat()}"
        raw = self.client.news(
            symbols.upper().replace(" ", ""), min(int(limit), 15), start
        )
        return [
            {
                "headline": n.get("headline"),
                "summary": (n.get("summary") or "")[:300],
                "symbols": n.get("symbols"),
                "created_at": n.get("created_at"),
                "source": n.get("source"),
            }
            for n in raw.get("news", [])
        ]

    def _universe(self, symbol):
        """Return (reject reason, metrics) for a symbol."""
        try:
            asset = self.client.asset(symbol)
        except AlpacaError:
            return "unknown symbol", {}
        today = date.fromisoformat(self.ctx.day)
        end = f"{(today - timedelta(days=1)).isoformat()}T23:59:59Z"
        start = f"{(today - timedelta(days=45)).isoformat()}T00:00:00Z"
        bars = (
            self.client.bars(symbol, "1Day", start, end, 60, "sip").get("bars") or {}
        ).get(symbol, [])[-20:]
        avg_vol = mean(b["v"] for b in bars) if bars else None
        avg_dollar = mean(b["v"] * b["c"] for b in bars) if bars else None
        snap = self.client.snapshots(symbol).get(symbol, {})
        price = (snap.get("latestTrade") or {}).get("p") or (
            snap.get("dailyBar") or {}
        ).get("c")
        reason = guardrails.universe_reject_reason(
            self.params, asset, price, avg_vol, avg_dollar
        )
        metrics = {
            "symbol": symbol,
            "name": asset.get("name"),
            "price": price,
            "avg_volume_20d": round(avg_vol) if avg_vol else None,
            "avg_dollar_volume_20d": round(avg_dollar) if avg_dollar else None,
        }
        return reason, metrics

    def check_symbol(self, symbol):
        """Return whether a symbol passes the universe rules, with metrics."""
        reason, metrics = self._universe(symbol.upper().strip())
        return {"passes": reason is None, "reject_reason": reason, **metrics}

    # Writes (guarded) ------------------------------------------------------

    def place_bracket_order(self, symbol, entry_limit, stop):
        """Place a guarded long bracket order. Code sizes it and sets the target."""
        symbol = symbol.upper().strip()
        entry, stop = float(entry_limit), float(stop)
        acct = self.client.account()
        positions = self.client.positions()
        active = self._active_orders()
        pending = {
            o["symbol"]
            for o in active
            if o["side"] == "buy" and not o.get("parent_order_id")
        }
        reason, metrics = self._universe(symbol)
        facts = {
            "market_open": bool(self.client.clock().get("is_open")),
            "now_et": self.ctx.now_et(),
            "start_equity": _f(acct.get("last_equity")),
            "equity_now": _f(acct.get("equity")) or 0,
            "symbol": symbol,
            "held_symbols": {p["symbol"] for p in positions},
            "pending_symbols": pending,
            "orders_run": self.ctx.orders_run,
            "orders_day": self._orders_today(),
            "universe_reason": reason,
            "last_price": metrics.get("price"),
            "entry": entry,
            "stop": stop,
        }
        sizing, error = guardrails.evaluate_entry(self.params, facts)
        if error:
            self.journal(
                "rejected", symbol=symbol, entry=entry, stop=stop, reason=error
            )
            return {"ok": False, "rejected_by_guardrail": error}
        cid = f"{self.ctx.day.replace('-', '')}-s{self.ctx.slot}-{symbol}"
        self.journal("intent", action="bracket_buy", client_order_id=cid, **sizing)
        if self.ctx.dry_run:
            self.ctx.orders_run += 1
            self.journal("result", client_order_id=cid, simulated=True)
            return {"ok": True, "simulated": True, **sizing}
        body = {
            "symbol": symbol,
            "qty": str(sizing["qty"]),
            "side": "buy",
            "type": "limit",
            "limit_price": str(sizing["entry"]),
            "time_in_force": "day",
            "order_class": "bracket",
            "take_profit": {"limit_price": str(sizing["target"])},
            "stop_loss": {"stop_price": str(sizing["stop"])},
            "client_order_id": cid,
        }
        try:
            order = self.client.submit_order(body)
        except AlpacaError as exc:
            self.journal("error", client_order_id=cid, error=str(exc))
            return {"ok": False, "error": str(exc)}
        self.ctx.orders_run += 1
        self.journal(
            "result",
            client_order_id=cid,
            order_id=order.get("id"),
            status=order.get("status"),
        )
        return {
            "ok": True,
            "order_id": order.get("id"),
            "status": order.get("status"),
            **sizing,
        }

    def move_stop_to(self, symbol, new_stop):
        """Tighten the protective stop on a long position (never widen)."""
        symbol, new_stop = symbol.upper().strip(), float(new_stop)
        stops = [
            o
            for o in self._active_orders()
            if o["symbol"] == symbol
            and o["side"] == "sell"
            and o["type"] in ("stop", "stop_limit")
        ]
        if not stops:
            return {"ok": False, "error": "no active stop order found"}
        order = stops[0]
        last = self.get_snapshots(symbol).get(symbol, {}).get("price")
        error = guardrails.stop_move_reason(_f(order["stop_price"]), new_stop, last)
        if error:
            self.journal("rejected", symbol=symbol, new_stop=new_stop, reason=error)
            return {"ok": False, "rejected_by_guardrail": error}
        self.journal("intent", action="move_stop", symbol=symbol, new_stop=new_stop)
        if self.ctx.dry_run:
            return {"ok": True, "simulated": True}
        try:
            self.client.replace_order(
                order["id"], {"stop_price": str(round(new_stop, 2))}
            )
        except AlpacaError as exc:
            self.journal("error", symbol=symbol, error=str(exc))
            return {"ok": False, "error": str(exc)}
        self.journal("result", action="move_stop", symbol=symbol, new_stop=new_stop)
        return {"ok": True}

    def close_position(self, symbol, reason):
        """Close one position now and record why."""
        symbol = symbol.upper().strip()
        self.journal("intent", action="close_position", symbol=symbol, why=reason)
        if self.ctx.dry_run:
            return {"ok": True, "simulated": True}
        for order in self._active_orders():
            if order["symbol"] == symbol:
                try:
                    self.client.cancel_order(order["id"])
                except AlpacaError as exc:
                    logger.warning("cancel failed for %s: %s", order["id"], exc)
        try:
            self.client.close_position(symbol)
        except AlpacaError as exc:
            self.journal("error", symbol=symbol, error=str(exc))
            return {"ok": False, "error": str(exc)}
        self.journal("result", action="close_position", symbol=symbol)
        return {"ok": True}

    def journal_note(self, kind, text):
        """Record a decision, skipped signal or observation."""
        self.journal(
            kind if kind in ("decision", "skipped", "note") else "note", text=text
        )
        return {"ok": True}

    def save_handoff(self, handoff):
        """Overwrite the handoff record for the next run."""
        if not isinstance(handoff, dict):
            return {"ok": False, "error": "handoff must be an object"}
        handoff["updated_at"] = now_iso()
        handoff["updated_by_slot"] = self.ctx.slot
        self.store.put_json("state/progress.json", handoff)
        return {"ok": True}

    def send_report(self, title, message):
        """Send the midday or end-of-day report to the phone."""
        if self.ctx.slot not in REPORT_SLOTS:
            return {"ok": False, "error": "reports are only sent in the report slots"}
        prefix = "[DRY RUN] " if self.ctx.dry_run else ""
        sent = notify.send(self.ctx.ntfy_topic, prefix + title, message, tags="chart")
        self.ctx.report_sent = self.ctx.report_sent or sent
        return {"ok": sent}

    # Dispatch --------------------------------------------------------------

    def specs(self):
        """Return Bedrock tool specs."""
        sym = {"type": "string", "description": "Ticker or comma-separated tickers"}
        return [
            _spec(
                "get_account", "Equity, start-of-day equity, day P&L, loss-limit flag."
            ),
            _spec("get_positions", "Open positions with P&L."),
            _spec("get_open_orders", "Live and pending orders including bracket legs."),
            _spec(
                "get_movers",
                "Top gainers and losers, already filtered by minimum price.",
                {"top": {"type": "integer"}},
            ),
            _spec(
                "get_most_actives",
                "Most active symbols by volume.",
                {"top": {"type": "integer"}},
            ),
            _spec(
                "get_snapshots",
                "Latest price, prior close, day range.",
                {"symbols": sym},
                ["symbols"],
            ),
            _spec(
                "get_bars",
                "OHLCV bars. Intraday timeframes default to today since the open.",
                {
                    "symbols": sym,
                    "timeframe": {"type": "string"},
                    "start": {"type": "string", "description": "RFC3339, optional"},
                    "limit": {"type": "integer"},
                },
                ["symbols"],
            ),
            _spec(
                "get_news",
                "Recent headlines for symbols.",
                {"symbols": sym, "limit": {"type": "integer"}},
                ["symbols"],
            ),
            _spec(
                "check_symbol",
                "Universe check with price and 20-day volume metrics.",
                {"symbol": {"type": "string"}},
                ["symbol"],
            ),
            _spec(
                "place_bracket_order",
                "Long bracket entry. Provide a limit price and a stop. Size and "
                "target are computed and enforced by code; violations are rejected.",
                {
                    "symbol": {"type": "string"},
                    "entry_limit": {"type": "number"},
                    "stop": {"type": "number"},
                },
                ["symbol", "entry_limit", "stop"],
            ),
            _spec(
                "move_stop_to",
                "Tighten the stop on an open position. Never widens.",
                {"symbol": {"type": "string"}, "new_stop": {"type": "number"}},
                ["symbol", "new_stop"],
            ),
            _spec(
                "close_position",
                "Close a position now and record the reason.",
                {"symbol": {"type": "string"}, "reason": {"type": "string"}},
                ["symbol", "reason"],
            ),
            _spec(
                "journal_note",
                "Record a decision, skipped signal or note. "
                "kind: decision, skipped, note.",
                {"kind": {"type": "string"}, "text": {"type": "string"}},
                ["kind", "text"],
            ),
            _spec(
                "save_handoff",
                "Overwrite the handoff record (the whole progress object).",
                {"handoff": {"type": "object"}},
                ["handoff"],
            ),
            _spec(
                "send_report",
                "Send the midday or end-of-day report (report slots only).",
                {"title": {"type": "string"}, "message": {"type": "string"}},
                ["title", "message"],
            ),
        ]

    def call(self, name, args):
        """Run a tool by name and return a JSON string for the model."""
        handlers = {
            "get_account": self.get_account,
            "get_positions": self.get_positions,
            "get_open_orders": self.get_open_orders,
            "get_movers": self.get_movers,
            "get_most_actives": self.get_most_actives,
            "get_snapshots": self.get_snapshots,
            "get_bars": self.get_bars,
            "get_news": self.get_news,
            "check_symbol": self.check_symbol,
            "place_bracket_order": self.place_bracket_order,
            "move_stop_to": self.move_stop_to,
            "close_position": self.close_position,
            "journal_note": self.journal_note,
            "save_handoff": self.save_handoff,
            "send_report": self.send_report,
        }
        handler = handlers.get(name)
        if handler is None:
            return json.dumps({"error": f"unknown tool {name}"})
        try:
            result = handler(**args)
        except AlpacaError as exc:
            result = {"error": str(exc)}
        except (TypeError, ValueError, KeyError) as exc:
            result = {"error": f"bad arguments: {exc}"}
        text = json.dumps(result, default=str)
        if len(text) > MAX_RESULT_CHARS:
            text = text[:MAX_RESULT_CHARS] + '..."truncated"'
        return text
