"""Thin Alpaca REST client using only the standard library."""

import json
import time
import urllib.error
import urllib.parse
import urllib.request

TRADING_URL = "https://paper-api.alpaca.markets"
DATA_URL = "https://data.alpaca.markets"


class AlpacaError(Exception):
    """Raised for non-2xx Alpaca responses."""

    def __init__(self, status, body):
        """Store the HTTP status and response body."""
        super().__init__(status, body)
        self.status = status
        self.body = body

    def __str__(self):
        """Render a short, log-safe message."""
        return f"Alpaca HTTP {self.status}: {str(self.body)[:300]}"


class AlpacaClient:
    """Alpaca trading and market data calls."""

    def __init__(self, key_id, secret_key, trading_url=TRADING_URL):
        """Create a client bound to one set of credentials."""
        self.trading_url = trading_url
        self._headers = {
            "APCA-API-KEY-ID": key_id,
            "APCA-API-SECRET-KEY": secret_key,
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def _request(self, method, base, path, params=None, body=None, retries=0):
        url = base + path
        if params:
            clean = {k: v for k, v in params.items() if v is not None}
            url += "?" + urllib.parse.urlencode(clean)
        data = json.dumps(body).encode("utf-8") if body is not None else None
        for attempt in range(retries + 1):
            request = urllib.request.Request(
                url, data=data, method=method, headers=self._headers
            )
            try:
                with urllib.request.urlopen(request, timeout=20) as response:
                    raw = response.read().decode("utf-8")
                    return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")
                if exc.code in (429, 500, 502, 503, 504) and attempt < retries:
                    time.sleep(1.5 * (attempt + 1))
                    continue
                raise AlpacaError(exc.code, detail) from exc
            except urllib.error.URLError as exc:
                if attempt < retries:
                    time.sleep(1.5 * (attempt + 1))
                    continue
                raise AlpacaError(0, str(exc)) from exc
        raise AlpacaError(0, "unreachable")

    def _trading(self, method, path, params=None, body=None, retries=0):
        return self._request(method, self.trading_url, path, params, body, retries)

    def _data(self, path, params=None):
        return self._request("GET", DATA_URL, path, params, retries=2)

    # Trading ---------------------------------------------------------------

    def account(self):
        """Return the account object."""
        return self._trading("GET", "/v2/account", retries=2)

    def clock(self):
        """Return the market clock."""
        return self._trading("GET", "/v2/clock", retries=2)

    def calendar(self, day):
        """Return calendar entries for one YYYY-MM-DD date."""
        return self._trading(
            "GET", "/v2/calendar", {"start": day, "end": day}, retries=2
        )

    def positions(self):
        """Return open positions."""
        return self._trading("GET", "/v2/positions", retries=2)

    def orders(self, after):
        """Return orders since a timestamp, with bracket legs nested."""
        return self._trading(
            "GET",
            "/v2/orders",
            {"status": "all", "nested": "true", "limit": 100, "after": after},
            retries=2,
        )

    def asset(self, symbol):
        """Return the asset record for a symbol."""
        return self._trading("GET", f"/v2/assets/{symbol}", retries=2)

    def submit_order(self, body):
        """Submit an order. Callers must set a client_order_id."""
        return self._trading("POST", "/v2/orders", body=body)

    def replace_order(self, order_id, body):
        """Patch an existing order."""
        return self._trading("PATCH", f"/v2/orders/{order_id}", body=body)

    def cancel_order(self, order_id):
        """Cancel one order."""
        return self._trading("DELETE", f"/v2/orders/{order_id}")

    def cancel_all_orders(self):
        """Cancel every open order."""
        return self._trading("DELETE", "/v2/orders")

    def close_all_positions(self):
        """Liquidate all positions, cancelling open orders first."""
        return self._trading("DELETE", "/v2/positions", {"cancel_orders": "true"})

    def close_position(self, symbol):
        """Liquidate one position."""
        return self._trading("DELETE", f"/v2/positions/{symbol}")

    def order_by_client_id(self, client_order_id):
        """Look up an order by its client order id."""
        return self._trading(
            "GET",
            "/v2/orders:by_client_order_id",
            {"client_order_id": client_order_id},
            retries=2,
        )

    # Market data -----------------------------------------------------------

    def snapshots(self, symbols, feed="iex"):
        """Return snapshots for a comma-separated symbol list."""
        return self._data("/v2/stocks/snapshots", {"symbols": symbols, "feed": feed})

    def bars(self, symbols, timeframe, start, end, limit, feed):
        """Return historical bars."""
        return self._data(
            "/v2/stocks/bars",
            {
                "symbols": symbols,
                "timeframe": timeframe,
                "start": start,
                "end": end,
                "limit": limit,
                "feed": feed,
                "adjustment": "split",
                "sort": "asc",
            },
        )

    def movers(self, top):
        """Return market movers."""
        return self._data("/v1beta1/screener/stocks/movers", {"top": top})

    def most_actives(self, top):
        """Return most active stocks by volume."""
        return self._data(
            "/v1beta1/screener/stocks/most-actives", {"by": "volume", "top": top}
        )

    def news(self, symbols, limit, start):
        """Return recent news."""
        return self._data(
            "/v1beta1/news",
            {"symbols": symbols, "limit": limit, "start": start, "sort": "desc"},
        )
