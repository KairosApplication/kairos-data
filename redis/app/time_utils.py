"""Limites da semana local do Kairos (segunda a segunda, São Paulo)."""

from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

SAO_PAULO = ZoneInfo("America/Sao_Paulo")


def week_window(reference: datetime) -> tuple[datetime, datetime]:
    """Retorna início (inclusivo) e fim (exclusivo) da semana local.

    Ambos são datetimes com fuso horário America/Sao_Paulo.
    """
    if reference.tzinfo is None or reference.utcoffset() is None:
        raise ValueError("A data deve informar fuso horário.")

    local = reference.astimezone(SAO_PAULO)
    monday = local.date() - timedelta(days=local.weekday())
    start = datetime.combine(monday, time.min, tzinfo=SAO_PAULO)
    end = datetime.combine(monday + timedelta(days=7), time.min, tzinfo=SAO_PAULO)
    return start, end


def now_utc() -> datetime:
    return datetime.now(timezone.utc)
