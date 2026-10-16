from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest

from app.time_utils import week_window


def test_week_starts_monday_at_midnight_in_sao_paulo():
    start, end = week_window(datetime(2026, 10, 16, 11, 0, tzinfo=timezone.utc))
    assert start.isoformat() == "2026-10-12T00:00:00-03:00"
    assert end.isoformat() == "2026-10-19T00:00:00-03:00"


def test_new_week_changes_key_after_monday():
    sunday = datetime(2026, 10, 18, 23, 59, tzinfo=ZoneInfo("America/Sao_Paulo"))
    monday = datetime(2026, 10, 19, 0, 0, tzinfo=ZoneInfo("America/Sao_Paulo"))
    _, old_end = week_window(sunday)
    new_start, _ = week_window(monday)
    assert old_end == new_start


def test_naive_datetime_rejected():
    with pytest.raises(ValueError):
        week_window(datetime(2026, 10, 16, 8, 0))
