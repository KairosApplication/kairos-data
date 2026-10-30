"""Teste de integracao do grafo de exemplo, sem mutar dados."""
from neo4j import GraphDatabase

from app.settings import NEO4J_DATABASE, NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER


def scalar(driver, query):
    rows, _, _ = driver.execute_query(query, database_=NEO4J_DATABASE)
    return rows[0][0]


def main():
    with GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD)) as driver:
        driver.verify_connectivity()
        assert scalar(driver, "MATCH (c:Company {id:990001}) RETURN count(c)") == 1
        assert scalar(driver, "MATCH (c:Company {id:990002}) RETURN count(c)") == 1
        assert scalar(driver, "MATCH (a:Alert {id:990061,company_id:990002}) RETURN count(a)") == 0
        rows, _, _ = driver.execute_query("""
            MATCH (al:Alert {id:990061,company_id:990001})-[:ON_SHELF]->(s:Shelf)<-[:HAS_SHELF]-(a:Aisle)
            MATCH (e:Employee {company_id:990001, position:'STOCKER'})
            WHERE EXISTS { MATCH (e)-[:ASSIGNED_TO_AISLE]->(a) }
               OR EXISTS { MATCH (e)-[:ASSIGNED_TO_SHELF]->(s) }
            RETURN DISTINCT e.id AS employee_id
        """, database_=NEO4J_DATABASE)
        assert {r["employee_id"] for r in rows} == {990011, 990012}
        print("OK: exemplo criado, responsaveis corretos, sem vazamento entre empresas")


if __name__ == "__main__":
    main()
