"""Operações de Redis: LIST + idempotência + EXPIREAT por semana."""

import json
from datetime import datetime

from redis import Redis

from app.schemas import RestockingEvent
from app.time_utils import week_window

# Executar atomicamente evita entradas duplicadas quando o backend tenta novamente.
# O Redis é cache, não substitui a tabela Restockings do PostgreSQL.
_LUA_APPEND_ONCE = """
local list_key = KEYS[1]
local seen_key = KEYS[2]
local payload = ARGV[1]
local max_size = tonumber(ARGV[2])
local expire_at = tonumber(ARGV[3])

if redis.call('EXISTS', seen_key) == 1 then
    return 0
end

redis.call('SET', seen_key, '1')
redis.call('LPUSH', list_key, payload)
redis.call('LTRIM', list_key, 0, max_size - 1)
redis.call('EXPIREAT', list_key, expire_at)
redis.call('EXPIREAT', seen_key, expire_at)
return 1
"""


def _keys(company_id: int, employee_id: int, reference: datetime) -> tuple[str, str]:
    start, _ = week_window(reference)
    base = f"kairos:company:{company_id}:stocker:{employee_id}:week:{start.date().isoformat()}"
    return f"{base}:restockings", f"{base}:seen"


def cache_restocking(client: Redis, event: RestockingEvent, max_items: int) -> bool:
    _, week_end = week_window(event.restocking_date)
    list_key, seen_base = _keys(event.company_id, event.employee_id, event.restocking_date)
    seen_key = f"{seen_base}:{event.restocking_id}"
    expires_at = int(week_end.timestamp())
    payload = event.model_dump_json()
    return bool(client.eval(_LUA_APPEND_ONCE, 2, list_key, seen_key, payload, max_items, expires_at))


def get_week_history(
    client: Redis, company_id: int, employee_id: int,
    reference: datetime, limit: int,
) -> tuple[int, list[RestockingEvent]]:
    list_key, _ = _keys(company_id, employee_id, reference)
    # LPUSH coloca as mais novas no início da lista.
    pipe = client.pipeline(transaction=False)
    pipe.llen(list_key)
    pipe.lrange(list_key, 0, limit - 1)
    total, raw_items = pipe.execute()
    return int(total), [RestockingEvent.model_validate(json.loads(item)) for item in raw_items]
