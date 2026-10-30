"""API interna: histórico de reposições da semana no Redis."""

import os
import secrets
from datetime import datetime
from functools import lru_cache
from typing import Annotated

import redis
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from redis import Redis

from app.schemas import CacheResult, RestockingEvent, WeekHistory
from app.store import cache_restocking, get_week_history
from app.time_utils import now_utc, week_window

load_dotenv()
app = FastAPI(title="Kairos Redis API", version="1.0.0")


@lru_cache
def get_redis() -> Redis:
    return redis.Redis.from_url(
        os.getenv("REDIS_URL", "redis://localhost:6379/0"),
        decode_responses=True,
        socket_connect_timeout=3,
        socket_timeout=3,
        health_check_interval=30,
    )


def verify_internal_key(x_internal_api_key: Annotated[str | None, Header()] = None) -> None:
    configured = os.getenv("KAIROS_INTERNAL_API_KEY", "")
    if not configured or configured == "SUBSTITUA_POR_UMA_CHAVE_ALEATORIA_LONGA":
        raise HTTPException(status_code=503, detail="Chave interna da API não configurada.")
    if not x_internal_api_key or not secrets.compare_digest(x_internal_api_key, configured):
        raise HTTPException(status_code=401, detail="Chave interna inválida.")


def redis_unavailable() -> HTTPException:
    return HTTPException(status_code=503, detail="Redis temporariamente indisponível.")


@app.get("/health")
def health(client: Redis = Depends(get_redis)) -> dict:
    try:
        client.ping()
        return {"status": "ok", "redis": "connected"}
    except redis.RedisError:
        raise redis_unavailable()


@app.post(
    "/v1/restockings/events", response_model=CacheResult,
    dependencies=[Depends(verify_internal_key)],
)
def create_restocking_event(
    event: RestockingEvent, client: Redis = Depends(get_redis),
) -> CacheResult:
    """Usar somente DEPOIS que a reposição foi confirmada no PostgreSQL."""
    now = now_utc()
    start, end = week_window(now)
    event_start, _ = week_window(event.restocking_date)
    if event_start != start:
        raise HTTPException(
            status_code=422,
            detail="Somente reposições da semana atual entram no cache; consulte o PostgreSQL para semanas passadas.",
        )
    if event.restocking_date.timestamp() > now.timestamp() + 300:
        raise HTTPException(status_code=422, detail="Data da reposição está no futuro.")

    try:
        max_items = int(os.getenv("MAX_RESTOCKINGS_PER_WEEK", "500"))
        if max_items <= 0:
            raise ValueError("MAX_RESTOCKINGS_PER_WEEK deve ser positivo")
        inserted = cache_restocking(client, event, max_items)
    except redis.RedisError:
        raise redis_unavailable()
    return CacheResult(cached=inserted, duplicate=not inserted, week_start=start, expires_at=end)


@app.get(
    "/v1/restockings/week", response_model=WeekHistory,
    dependencies=[Depends(verify_internal_key)],
)
def list_week_restockings(
    company_id: Annotated[int, Query(gt=0)],
    employee_id: Annotated[int, Query(gt=0)],
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
    client: Redis = Depends(get_redis),
) -> WeekHistory:
    """Histórico da semana atual, ordenado das reposições recentes às antigas."""
    current_time = now_utc()
    start, end = week_window(current_time)
    try:
        total, items = get_week_history(client, company_id, employee_id, current_time, limit)
    except redis.RedisError:
        raise redis_unavailable()
    return WeekHistory(
        company_id=company_id,
        employee_id=employee_id,
        week_start=start,
        week_end=end,
        total_cached=total,
        items=items,
    )
