"""Aplica constraints e seed de demonstracao; idempotente."""
import argparse
from pathlib import Path

from neo4j import GraphDatabase

from app.settings import NEO4J_DATABASE, NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER

ROOT = Path(__file__).resolve().parents[1]


def statements(path: Path):
    # Nos arquivos do projeto, cada comando termina em ';'.
    # Comentarios usam apenas '//', em linhas separadas.
    content = "\n".join(
        line for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("//")
    )
    for chunk in content.split(";"):
        if chunk.strip():
            yield chunk.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", action="store_true", help="Inclui dados ficticios de demonstracao")
    args = parser.parse_args()

    if not NEO4J_PASSWORD:
        raise SystemExit("Defina NEO4J_PASSWORD em neo4j/.env")

    paths = [ROOT / "cypher/01_schema.cypher"]
    if args.seed:
        paths.append(ROOT / "cypher/02_seed_dev.cypher")

    with GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD)) as driver:
        driver.verify_connectivity()
        for path in paths:
            count = 0
            for statement in statements(path):
                driver.execute_query(statement, database_=NEO4J_DATABASE)
                count += 1
            print(f"OK: {path.name}: {count} comandos aplicados")
    print("Grafo pronto.")


if __name__ == "__main__":
    main()
