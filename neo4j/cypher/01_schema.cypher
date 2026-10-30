// KAIROS | Grafo de responsabilidades e impacto da reposicao
// IDs sao os IDs globais do PostgreSQL. Neo4j e uma projecao de leitura.
// Compativel com Neo4j Community 5.26. Execute quantas vezes quiser.

CREATE CONSTRAINT company_id_unique IF NOT EXISTS FOR (n:Company) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT employee_id_unique IF NOT EXISTS FOR (n:Employee) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT sector_id_unique IF NOT EXISTS FOR (n:Sector) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT aisle_id_unique IF NOT EXISTS FOR (n:Aisle) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT shelf_id_unique IF NOT EXISTS FOR (n:Shelf) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT product_id_unique IF NOT EXISTS FOR (n:Product) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT alert_id_unique IF NOT EXISTS FOR (n:Alert) REQUIRE n.id IS UNIQUE;

CREATE INDEX employee_by_company_position IF NOT EXISTS FOR (n:Employee) ON (n.company_id, n.position);
CREATE INDEX alert_by_company_status IF NOT EXISTS FOR (n:Alert) ON (n.company_id, n.status);
CREATE INDEX product_by_company_name IF NOT EXISTS FOR (n:Product) ON (n.company_id, n.name);
