"""API interna de leitura: o aplicativo nao deve acessar Neo4j diretamente."""
from contextlib import asynccontextmanager
from hmac import compare_digest

from fastapi import Depends, FastAPI, Header, HTTPException, Path
from neo4j import GraphDatabase

from app import queries
from app.settings import (
    KAIROS_NEO4J_API_KEY,
    NEO4J_DATABASE,
    NEO4J_PASSWORD,
    NEO4J_URI,
    NEO4J_USER,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    if not NEO4J_PASSWORD or not KAIROS_NEO4J_API_KEY or KAIROS_NEO4J_API_KEY.startswith("SUBSTITUA"):
        raise RuntimeError("Configure senha do Neo4j e chave interna em neo4j/.env")
    driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
    driver.verify_connectivity()
    app.state.driver = driver
    yield
    driver.close()


app = FastAPI(title="Kairos Graph API", version="1.0.0", lifespan=lifespan)


def internal_auth(x_internal_api_key: str | None = Header(default=None)):
    if not x_internal_api_key or not compare_digest(x_internal_api_key, KAIROS_NEO4J_API_KEY):
        raise HTTPException(status_code=401, detail="Invalid internal API key")


def graph_query(query: str, **params) -> list[dict]:
    rows, _, _ = app.state.driver.execute_query(query, database_=NEO4J_DATABASE, **params)
    return [dict(row) for row in rows]


@app.get("/health")
def health():
    try:
        graph_query("RETURN 1 AS ok")
        return {"status": "ok", "neo4j": "connected"}
    except Exception:
        raise HTTPException(status_code=503, detail="Neo4j unavailable")


@app.get("/v1/companies/{company_id}/alerts/{alert_id}/stockers", dependencies=[Depends(internal_auth)])
def stockers_for_alert(company_id: int = Path(ge=1), alert_id: int = Path(ge=1)):
    found = graph_query(
        "MATCH (a:Alert {id: $alert_id, company_id: $company_id}) RETURN a.id AS id",
        alert_id=alert_id, company_id=company_id,
    )
    if not found:
        raise HTTPException(status_code=404, detail="Alert not found for this company")
    return {"company_id": company_id, "alert_id": alert_id,
            "stockers": graph_query(queries.ALERT_CANDIDATES, company_id=company_id, alert_id=alert_id)}


@app.get("/v1/companies/{company_id}/aisles/{aisle_id}/stockers", dependencies=[Depends(internal_auth)])
def stockers_for_aisle(company_id: int = Path(ge=1), aisle_id: int = Path(ge=1)):
    return {"company_id": company_id, "aisle_id": aisle_id,
            "stockers": graph_query(queries.AISLE_STOCKERS, company_id=company_id, aisle_id=aisle_id)}


@app.get("/v1/companies/{company_id}/employees/{employee_id}/coverage", dependencies=[Depends(internal_auth)])
def coverage(company_id: int = Path(ge=1), employee_id: int = Path(ge=1)):
    return {"company_id": company_id, "employee_id": employee_id,
            "aisles": graph_query(queries.EMPLOYEE_COVERAGE, company_id=company_id, employee_id=employee_id)}
