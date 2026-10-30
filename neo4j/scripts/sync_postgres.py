"""Projeta entidades e relacionamentos do PostgreSQL para Neo4j.

PostgreSQL e a fonte de verdade. Sincronizacao manual de snapshot por MERGE.
Relacoes invalidas (empresas diferentes) ficam de fora e sao reportadas.
Remocoes no PostgreSQL nao sao refletidas automaticamente neste MVP.
"""
import argparse

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

BATCH_SIZE = 500

STEPS = [
    (
        "companies",
        "SELECT id, name FROM Companies ORDER BY id",
        """
        UNWIND $rows AS row
        MERGE (c:Company {id: row.id})
        SET c.name = row.name
        """,
    ),
    (
        "sectors",
        "SELECT id, company_id, name, type FROM Sectors ORDER BY id",
        """
        UNWIND $rows AS row
        MATCH (c:Company {id: row.company_id})
        MERGE (s:Sector {id: row.id})
        SET s.name = row.name, s.type = row.type, s.company_id = row.company_id
        MERGE (c)-[:HAS_SECTOR]->(s)
        """,
    ),
    (
        "aisles",
        """SELECT a.id, a.sector_id, a.position, s.company_id
        FROM Aisles a JOIN Sectors s ON s.id = a.sector_id ORDER BY a.id""",
        """
        UNWIND $rows AS row
        MATCH (s:Sector {id: row.sector_id, company_id: row.company_id})
        MERGE (a:Aisle {id: row.id})
        SET a.position = row.position, a.company_id = row.company_id
        MERGE (s)-[:HAS_AISLE]->(a)
        """,
    ),
    (
        "shelves",
        """SELECT sh.id, sh.aisle_id, sh.maximum_capacity, s.company_id
        FROM Shelves sh JOIN Aisles a ON a.id = sh.aisle_id
        JOIN Sectors s ON s.id = a.sector_id ORDER BY sh.id""",
        """
        UNWIND $rows AS row
        MATCH (a:Aisle {id: row.aisle_id, company_id: row.company_id})
        MERGE (sh:Shelf {id: row.id})
        SET sh.maximum_capacity = row.maximum_capacity, sh.company_id = row.company_id
        MERGE (a)-[:HAS_SHELF]->(sh)
        """,
    ),
    (
        "employees",
        """SELECT e.id, e.company_id, e.position,
        (u.name || ' ' || u.last_name) AS name
        FROM Employees e JOIN Users u ON u.id = e.users_id
        WHERE e.position IN ('MANAGER', 'STOCKER', 'CASHIER')
        ORDER BY e.id""",
        """
        UNWIND $rows AS row
        MATCH (c:Company {id: row.company_id})
        MERGE (e:Employee {id: row.id})
        SET e.company_id = row.company_id, e.position = row.position, e.name = row.name
        MERGE (e)-[:WORKS_FOR]->(c)
        """,
    ),
    (
        "products",
        "SELECT id, company_id, name, brand FROM Products ORDER BY id",
        """
        UNWIND $rows AS row
        MATCH (c:Company {id: row.company_id})
        MERGE (p:Product {id: row.id})
        SET p.name = row.name, p.brand = row.brand, p.company_id = row.company_id
        MERGE (p)-[:BELONGS_TO]->(c)
        """,
    ),
    (
        "employee_aisles_valid",
        """SELECT ea.employee_id, ea.aisle_id
        FROM Employee_Aisles ea
        JOIN Employees e ON e.id = ea.employee_id
        JOIN Aisles a ON a.id = ea.aisle_id
        JOIN Sectors s ON s.id = a.sector_id
        WHERE e.position = 'STOCKER' AND e.company_id = s.company_id
        ORDER BY ea.id""",
        """
        UNWIND $rows AS row
        MATCH (e:Employee {id: row.employee_id, position: 'STOCKER'})
        MATCH (a:Aisle {id: row.aisle_id, company_id: e.company_id})
        MERGE (e)-[:ASSIGNED_TO_AISLE]->(a)
        """,
    ),
    (
        "shelf_employees_valid",
        """SELECT se.employee_id, se.shelf_id
        FROM Shelf_Employees se
        JOIN Employees e ON e.id = se.employee_id
        JOIN Shelves sh ON sh.id = se.shelf_id
        JOIN Aisles a ON a.id = sh.aisle_id
        JOIN Sectors s ON s.id = a.sector_id
        WHERE e.position = 'STOCKER' AND e.company_id = s.company_id
        ORDER BY se.id""",
        """
        UNWIND $rows AS row
        MATCH (e:Employee {id: row.employee_id, position: 'STOCKER'})
        MATCH (s:Shelf {id: row.shelf_id, company_id: e.company_id})
        MERGE (e)-[:ASSIGNED_TO_SHELF]->(s)
        """,
    ),
    (
        "product_shelves_valid",
        """SELECT ps.product_id, ps.shelf_id, ps.product_quantity AS quantity
        FROM Product_Shelves ps
        JOIN Products p ON p.id = ps.product_id
        JOIN Shelves sh ON sh.id = ps.shelf_id
        JOIN Aisles a ON a.id = sh.aisle_id
        JOIN Sectors s ON s.id = a.sector_id
        WHERE p.company_id = s.company_id
        ORDER BY ps.id""",
        """
        UNWIND $rows AS row
        MATCH (s:Shelf {id: row.shelf_id})
        MATCH (p:Product {id: row.product_id, company_id: s.company_id})
        MERGE (s)-[stock:STOCKS]->(p)
        SET stock.quantity = row.quantity
        """,
    ),
    (
        "alerts_valid",
        """SELECT al.id, s.company_id, al.shelf_id, al.product_id,
        al.description, al.status, al.stockout_date::text AS stockout_date
        FROM Alerts al
        JOIN Shelves sh ON sh.id = al.shelf_id
        JOIN Aisles a ON a.id = sh.aisle_id
        JOIN Sectors s ON s.id = a.sector_id
        LEFT JOIN Products p ON p.id = al.product_id
        WHERE al.product_id IS NULL OR p.company_id = s.company_id
        ORDER BY al.id""",
        """
        UNWIND $rows AS row
        MATCH (s:Shelf {id: row.shelf_id, company_id: row.company_id})
        MERGE (a:Alert {id: row.id})
        SET a.company_id = row.company_id, a.description = row.description,
            a.status = row.status, a.stockout_date = row.stockout_date
        MERGE (a)-[:ON_SHELF]->(s)
        WITH a, row
        OPTIONAL MATCH (p:Product {id: row.product_id, company_id: row.company_id})
        FOREACH (_ IN CASE WHEN p IS NOT NULL THEN [1] ELSE [] END |
            MERGE (a)-[:ABOUT_PRODUCT]->(p)
        )
        """,
    ),
]

DIAGNOSTICS = [
    ("Employee_Aisles fora da empresa", """
      SELECT count(*) FROM Employee_Aisles ea JOIN Employees e ON e.id=ea.employee_id
      JOIN Aisles a ON a.id=ea.aisle_id JOIN Sectors s ON s.id=a.sector_id
      WHERE e.company_id <> s.company_id"""),
    ("Shelf_Employees fora da empresa", """
      SELECT count(*) FROM Shelf_Employees se JOIN Employees e ON e.id=se.employee_id
      JOIN Shelves sh ON sh.id=se.shelf_id JOIN Aisles a ON a.id=sh.aisle_id
      JOIN Sectors s ON s.id=a.sector_id WHERE e.company_id <> s.company_id"""),
    ("Product_Shelves fora da empresa", """
      SELECT count(*) FROM Product_Shelves ps JOIN Products p ON p.id=ps.product_id
      JOIN Shelves sh ON sh.id=ps.shelf_id JOIN Aisles a ON a.id=sh.aisle_id
      JOIN Sectors s ON s.id=a.sector_id WHERE p.company_id <> s.company_id"""),
    ("Alerts fora da empresa", """
      SELECT count(*) FROM Alerts al JOIN Products p ON p.id=al.product_id
      JOIN Shelves sh ON sh.id=al.shelf_id JOIN Aisles a ON a.id=sh.aisle_id
      JOIN Sectors s ON s.id=a.sector_id WHERE p.company_id <> s.company_id"""),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="Nao sincroniza se houver relacoes entre empresas distintas")
    args = parser.parse_args()

    if not POSTGRES_DSN or not NEO4J_PASSWORD:
        raise SystemExit("Configure POSTGRES_DSN e NEO4J_PASSWORD em neo4j/.env")

    with psycopg.connect(POSTGRES_DSN, row_factory=dict_row) as pg:
        print("Diagnostico de integridade entre empresas:")
        invalid = 0
        with pg.cursor() as cursor:
            for label, sql in DIAGNOSTICS:
                cursor.execute(sql)
                value = cursor.fetchone()["count"]
                print(f"  {label}: {value} relacoes invalidas")
                invalid += value

        if invalid and args.strict:
            raise SystemExit("Sincronizacao cancelada: corrija os relacionamentos no PostgreSQL primeiro")
        if invalid:
            print("AVISO: relacoes entre empresas diferentes serao ignoradas, sem alterar o PostgreSQL")

        with GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD)) as driver:
            driver.verify_connectivity()
            for name, sql, cypher in STEPS:
                total = 0
                with pg.cursor(name=f"kairos_sync_{name}") as cursor:
                    cursor.execute(sql)
                    while rows := cursor.fetchmany(BATCH_SIZE):
                        driver.execute_query(cypher, rows=rows, database_=NEO4J_DATABASE)
                        total += len(rows)
                print(f"  {name}: {total} registros processados")

    print("Sincronizacao concluida. ATENCAO: o processo e manual, e delecoes nao sao propagadas.")


if __name__ == "__main__":
    main()
