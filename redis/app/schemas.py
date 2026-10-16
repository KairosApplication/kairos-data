"""Contratos de entrada e saída da API."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class RestockingEvent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    restocking_id: int = Field(gt=0)
    company_id: int = Field(gt=0)
    employee_id: int = Field(gt=0)
    product_id: int = Field(gt=0)
    shelf_id: int = Field(gt=0)
    inventory_id: int = Field(gt=0)
    restocked_quantity: int = Field(gt=0)
    qnt_avarias: int = Field(ge=0)
    restocking_date: datetime
    product_name: str | None = Field(default=None, max_length=100)

    @field_validator("restocking_date")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("restocking_date deve incluir fuso horário, ex.: -03:00.")
        return value

    @field_validator("qnt_avarias")
    @classmethod
    def check_avarias(cls, value: int, info) -> int:
        quantity = info.data.get("restocked_quantity")
        if quantity is not None and value > quantity:
            raise ValueError("qnt_avarias não pode exceder restocked_quantity.")
        return value


class CacheResult(BaseModel):
    cached: bool
    duplicate: bool
    week_start: datetime
    expires_at: datetime


class WeekHistory(BaseModel):
    company_id: int
    employee_id: int
    week_start: datetime
    week_end: datetime
    total_cached: int
    items: list[RestockingEvent]
