"""Testes isolados com Redis em memória via fakeredis[lua]."""

from datetime import datetime
from zoneinfo import ZoneInfo

import fakeredis
from fastapi.testclient import TestClient

from app.main import app, get_redis, verify_internal_key


def test_post_then_list_and_deduplicate():
    fake = fakeredis.FakeRedis(decode_responses=True)
    app.dependency_overrides[get_redis] = lambda: fake
    app.dependency_overrides[verify_internal_key] = lambda: None
    try:
        client = TestClient(app)
        date_now = datetime.now(ZoneInfo("America/Sao_Paulo")).isoformat()
        data = {
            "restocking_id": 991,
            "company_id": 5,
            "employee_id": 72,
            "product_id": 10,
            "shelf_id": 4,
            "inventory_id": 3,
            "restocked_quantity": 30,
            "qnt_avarias": 2,
            "restocking_date": date_now,
            "product_name": "Arroz",
        }
        first = client.post("/v1/restockings/events", json=data)
        assert first.status_code == 200, first.text
        assert first.json()["cached"] is True

        second = client.post("/v1/restockings/events", json=data)
        assert second.status_code == 200, second.text
        assert second.json()["duplicate"] is True

        week = client.get("/v1/restockings/week?company_id=5&employee_id=72")
        assert week.status_code == 200, week.text
        assert week.json()["total_cached"] == 1
        assert week.json()["items"][0]["qnt_avarias"] == 2

        other_company = client.get("/v1/restockings/week?company_id=6&employee_id=72")
        assert other_company.json()["items"] == []
    finally:
        app.dependency_overrides.clear()


def test_authentication_required(monkeypatch):
    fake = fakeredis.FakeRedis(decode_responses=True)
    app.dependency_overrides[get_redis] = lambda: fake
    monkeypatch.setenv("KAIROS_INTERNAL_API_KEY", "somente-testes")
    try:
        client = TestClient(app)
        response = client.get("/v1/restockings/week?company_id=1&employee_id=1")
        assert response.status_code == 401
        assert client.get(
            "/v1/restockings/week?company_id=1&employee_id=1",
            headers={"X-Internal-API-Key": "somente-testes"},
        ).status_code == 200
    finally:
        app.dependency_overrides.clear()
