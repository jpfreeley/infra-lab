"""Test setup: make the Lambda modules importable."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Synthetic limits used only by tests. These intentionally differ from any
# real configuration.
TEST_LIMITS = {
    "max_positions": 3,
    "max_position_pct": 0.30,
    "risk_pct": 0.01,
    "max_stop_pct": 0.05,
    "reward_r": 3.0,
    "daily_loss_halt_pct": 0.05,
    "last_entry_time": "13:00",
    "min_price": 10,
    "min_avg_volume": 1000000,
    "min_avg_dollar_volume": 50000000,
    "max_entry_deviation_pct": 0.02,
    "max_orders_per_run": 2,
    "max_orders_per_day": 4,
    "max_turns": 5,
    "max_run_cost_usd": 1.0,
}
