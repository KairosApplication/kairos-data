// KAIROS | Consultas para executar manualmente no Neo4j Browser
// Os IDs 990xxx referem-se somente aos dados de demonstracao.

// 1. Visualizar o grafo da empresa 990001:
MATCH (c:Company {id: 990001})<-[:WORKS_FOR]-(e:Employee)
RETURN c, e;

// 2. Responsaveis por alerta 990061: repositores do corredor OU da prateleira.
MATCH (a:Alert {id: 990061, company_id: 990001})-[:ON_SHELF]->(s:Shelf)<-[:HAS_SHELF]-(cor:Aisle)
MATCH (e:Employee {company_id: 990001, position: 'STOCKER'})
WHERE (e)-[:ASSIGNED_TO_AISLE]->(cor) OR (e)-[:ASSIGNED_TO_SHELF]->(s)
RETURN DISTINCT e.id AS funcionario_id, e.name AS funcionario, a.description AS alerta
ORDER BY funcionario;

// 3. Quais produtos estao nas prateleiras do corredor 990031?
MATCH (a:Aisle {id: 990031, company_id: 990001})-[:HAS_SHELF]->(s:Shelf)-[rel:STOCKS]->(p:Product)
WHERE p.company_id = 990001
RETURN a.id AS corredor, s.id AS prateleira, p.name AS produto, rel.quantity AS quantidade;

// 4. Conferir isolamento: alerta 990061 NAO aparece na empresa 990002.
MATCH (a:Alert {id: 990061, company_id: 990002})
RETURN count(a) AS deve_ser_zero;

// 5. Visualizar relacoes de uma empresa inteira (limite para nao sobrecarregar a interface).
MATCH path=(c:Company {id: 990001})-[:HAS_SECTOR]->(:Sector)-[:HAS_AISLE]->(:Aisle)-[:HAS_SHELF]->(:Shelf)
RETURN path LIMIT 30;
