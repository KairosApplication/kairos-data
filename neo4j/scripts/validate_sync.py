"""Confere a carga do PostgreSQL para o grafo Neo4j sem alterar os bancos.

Execute: python -m scripts.validate_sync
Nao conta os registros ficticios do seed 990xxx que nao pertencem as empresas do PostgreSQL.
"""
import sys

import psycopg
from neo4j import GraphDatabase
from psycopg.rows import dict_row

from app.settings import (
    NEO4J_DATABASE,
    NEO4J_PASSWORD,
    NEO4J_URI,
    NEO4J_USER,
    POSTGRES_DSN,
)

# Cada tuple: (nome, consulta PostgreSQL, consulta Neo4j)
CHECKS = [
    (
        "companies",
        "SELECT COUNT(*) AS n FROM Companies",
        "MATCH (n:Company) WHERE n.id IN $company_ids RETURN count(n) AS n",
    ),
    (
        "sectors",
        "SELECT COUNT(*) AS n FROM Sectors",
        "MATCH (n:Sector) WHERE n.company_id IN $company_ids RETURN count(n) AS n",
    ),
    (
        "aisles",
        "SELECT COUNT(*) AS n FROM Aisles",
        "MATCH (n:Aisle) WHERE n.company_id IN $company_ids RETURN count(n) AS n",
    ),
    (
        "shelves",
        "SELECT COUNT(*) AS n FROM Shelves",
        "MATCH (n:Shelf) WHERE n.company_id IN $company_ids RETURN count(n) AS n",
    ),
    (
        "employees",
        """SELECT COUNT(*) AS n FROM Employees e JOIN Users u ON u.id = e.users_id
             WHERE e.position IN ('MANAGER', 'STOCKER', 'CASHIER')""",
        "MATCH (n:Employee) WHERE n.company_id IN $company_ids RETURN count(n) AS n",
    ),
    (
        "products",
        "SELECT COUNT(*) AS n FROM Products",
        "MATCH (n:Product) WHERE n.company_id IN $company_ids RETURN count(n) AS n",
    ),
    (
        "alerts_valid",
        """SELECT COUNT(*) AS n FROM Alerts al
             JOIN Shelves sh ON sh.id = al.shelf_id
             JOIN Aisles ais ON ais.id = sh.aisle_id
             JOIN Sectors se ON se.id = ais.sector_id
             LEFT JOIN Products p ON p.id = al.product_id
             WHERE al.product_id IS NULL OR p.company_id = se.company_id""",
        "MATCH (n:Alert) WHERE n.company_id IN $company_ids RETURN count(n) AS n",
    ),
    (
        "assigned_aisles",
        """SELECT COUNT(*) AS n FROM Employee_Aisles ea
             JOIN Employees e ON e.id = ea.employee_id
             JOIN Aisles a ON a.id = ea.aisle_id
             JOIN Sectors s ON s.id = a.sector_id
             WHERE e.position = 'STOCKER' AND e.company_id = s.company_id""",
        """MATCH (e:Employee)-[r:ASSIGNED_TO_AISLE]->(a:Aisle)
             WHERE e.company_id IN $company_ids AND e.company_id = a.company_id
             RETURN count(r) AS n""",
    ),
    (
        "assigned_shelves",
        """SELECT COUNT(*) AS n FROM Shelf_Employees se
             JOIN Employees e ON e.id = se.employee_id
             JOIN Shelves sh ON sh.id = se.shelf_id
             JOIN Aisles a ON a.id = sh.aisle_id
             JOIN Sectors s ON s.id = a.sector_id
             WHERE e.position = 'STOCKER' AND e.company_id = s.company_id""",
        """MATCH (e:Employee)-[r:ASSIGNED_TO_SHELF]->(sh:Shelf)
             WHERE e.company_id IN $company_ids AND e.company_id = sh.company_id
             RETURN count(r) AS n""",
    ),
    (
        "stocks",
        """SELECT COUNT(*) AS n FROM Product_Shelves ps
             JOIN Products p ON p.id = ps.product_id
             JOIN Shelves sh ON sh.id = ps.shelf_id
             JOIN Aisles a ON a.id = sh.aisle_id
             JOIN Sectors s ON s.id = a.sector_id
             WHERE p.company_id = s.company_id""",
        """MATCH (sh:Shelf)-[r:STOCKS]->(p:Product)
             WHERE sh.company_id IN $company_ids AND sh.company_id = p.company_id
             RETURN count(r) AS n""",
    ),
]

INVALID_LINKS = [
    ("Employee_Aisles", """SELECT COUNT(*) AS n FROM Employee_Aisles ea
         JOIN Employees e ON e.id = ea.employee_id
         JOIN Aisles a ON a.id = ea.aisle_id
         JOIN Sectors s ON s.id = a.sector_id
         WHERE e.company_id <> s.company_id"""),
    ("Shelf_Employees", """SELECT COUNT(*) AS n FROM Shelf_Employees se
         JOIN Employees e ON e.id = se.employee_id
         JOIN Shelves sh ON sh.id = se.shelf_id
         JOIN Aisles a ON a.id = sh.aisle_id
         JOIN Sectors s ON s.id = a.sector_id
         WHERE e.company_id <> s.company_id"""),
    ("Product_Shelves", """SELECT COUNT(*) AS n FROM Product_Shelves ps
         JOIN Products p ON p.id = ps.product_id
         JOIN Shelves sh ON sh.id = ps.shelf_id
         JOIN Aisles a ON a.id = sh.aisle_id
         JOIN Sectors s ON s.id = a.sector_id
         WHERE p.company_id <> s.company_id"""),
    ("Alerts", """SELECT COUNT(*) AS n FROM Alerts al
         JOIN Products p ON p.id = al.product_id
         JOIN Shelves sh ON sh.id = al.shelf_id
         JOIN Aisles a ON a.id = sh.aisle_id
         JOIN Sectors s ON s.id = a.sector_id
         WHERE p.company_id <> s.company_id"""),
]

CROSS_GRAPH = """
MATCH (e:Employee)-[r:ASSIGNED_TO_AISLE|ASSIGNED_TO_SHELF]->(n)
WHERE e.company_id <> n.company_id RETURN count(r) AS n
"""


def pg_count(cursor, sql):
    cursor.execute(sql)
    return int(cursor.fetchone()["n"])


def neo_count(driver, sql, **kwargs):
    records, _, _ = driver.execute_query(sql, database_=NEO4J_DATABASE, **kwargs)
    return int(records[0]["n"])


def main():
    if not POSTGRES_DSN or not NEO4J_PASSWORD:
        raise SystemExit("Configure POSTGRES_DSN e NEO4J_PASSWORD no .env do projeto")

    failed = False
    with psycopg.connect(POSTGRES_DSN, row_factory=dict_row) as conn, \
         GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD)) as driver:
        driver.verify_connectivity()
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM Companies ORDER BY id")
            company_ids = [row["id"] for row in cur.fetchall()]
            if not company_ids:
                raise SystemExit("PostgreSQL nao possui empresas para sincronizar")

            print("VALIDACAO DA ORIGEM (PostgreSQL)")
            for label, sql in INVALID_LINKS:
                invalid = pg_count(cur, sql)
                print(f"  {label}: {invalid} relacoes entre empresas diferentes")
                failed |= invalid != 0

            print("\nCONFERENCIA DO GRAFO (PostgreSQL x Neo4j)")
            for label, pg_sql, neo_sql in CHECKS:
                source = pg_count(cur, pg_sql)
                target = neo_count(driver, neo_sql, company_ids=company_ids)
                ok = source == target
                print(f"  {'OK' if ok else 'FALHOU'} {label}: PostgreSQL={source}, Neo4j={target}")
                failed |= not ok

            invalid_graph = neo_count(driver, CROSS_GRAPH)
            print(f"  {'OK' if invalid_graph == 0 else 'FALHOU'} atribuicoes cruzadas no grafo: {invalid_graph}")
            failed |= invalid_graph != 0

            cur.execute("""SELECT al.id AS alert_id, s.company_id FROM Alerts al
                JOIN Shelves sh ON sh.id = al.shelf_id
                JOIN Aisles a ON a.id = sh.aisle_id
                JOIN Sectors s ON s.id = a.sector_id
                ORDER BY al.id LIMIT 1""")
            example = cur.fetchone()
            if example:
                cnt = neo_count(driver, """MATCH (:Alert {id: $alert_id, company_id: $company_id})
                    -[:ON_SHELF]->(sh:Shelf)<-[:HAS_SHELF]-(a:Aisle)
                    MATCH (e:Employee {company_id: $company_id, position: 'STOCKER'})
                    WHERE EXISTS { MATCH (e)-[:ASSIGNED_TO_AISLE]->(a) }
                       OR EXISTS { MATCH (e)-[:ASSIGNED_TO_SHELF]->(sh) }
                    RETURN count(DISTINCT e) AS n""",
                    alert_id=example["alert_id"], company_id=example["company_id"])
                print(f"  Alerta {example['alert_id']} da empresa {example['company_id']}: {cnt} repositor(es) encontrados")
                if cnt == 0:
                    print("  AVISO: esse alerta nao possui repositor atribuido (pode ser valido em dados reais)")

    if failed:
        print("\nFALHOU: existe divergencia entre PostgreSQL e Neo4j.")
        sys.exit(1)
    print("\nOK: PostgreSQL e Neo4j consistentes para as verificacoes implementadas.")


if __name__ == "__main__":
    main()
