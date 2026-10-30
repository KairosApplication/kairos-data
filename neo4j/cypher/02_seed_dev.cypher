// KAIROS | Dados ficticios isolados. IDs 990xxx reservados a demonstracao.
// Reexecutavel sem duplicar nos ou arestas. Nao altera o PostgreSQL.

MERGE (c:Company {id: 990001}) SET c.name = 'Mercado Aurora (DEMO)';
MERGE (c:Company {id: 990002}) SET c.name = 'Mercado Horizonte (DEMO)';

MERGE (s:Sector {id: 990021}) SET s.name = 'Mercearia', s.type = 'SALES_FLOOR', s.company_id = 990001;
MERGE (s:Sector {id: 990022}) SET s.name = 'Mercearia', s.type = 'SALES_FLOOR', s.company_id = 990002;
MERGE (a:Aisle {id: 990031}) SET a.position = 1, a.company_id = 990001;
MERGE (a:Aisle {id: 990032}) SET a.position = 1, a.company_id = 990002;
MERGE (s:Shelf {id: 990041}) SET s.maximum_capacity = 150, s.company_id = 990001;
MERGE (s:Shelf {id: 990042}) SET s.maximum_capacity = 150, s.company_id = 990002;

MERGE (e:Employee {id: 990011}) SET e.name = 'Lucas Silva', e.position = 'STOCKER', e.company_id = 990001;
MERGE (e:Employee {id: 990012}) SET e.name = 'Mariana Souza', e.position = 'STOCKER', e.company_id = 990001;
MERGE (e:Employee {id: 990013}) SET e.name = 'Pedro Oliveira', e.position = 'MANAGER', e.company_id = 990001;
MERGE (e:Employee {id: 990014}) SET e.name = 'Ana Pereira', e.position = 'STOCKER', e.company_id = 990002;

MERGE (p:Product {id: 990051}) SET p.name = 'Arroz Integral 1kg', p.brand = 'Kairos Demo', p.company_id = 990001;
MERGE (p:Product {id: 990052}) SET p.name = 'Feijao Carioca 1kg', p.brand = 'Kairos Demo', p.company_id = 990002;
MERGE (a:Alert {id: 990061}) SET a.description = 'Reposicao necessaria: arroz', a.status = 'OPEN', a.company_id = 990001;
MERGE (a:Alert {id: 990062}) SET a.description = 'Reposicao necessaria: feijao', a.status = 'OPEN', a.company_id = 990002;

MATCH (c:Company {id: 990001}), (s:Sector {id: 990021}) MERGE (c)-[:HAS_SECTOR]->(s);
MATCH (c:Company {id: 990002}), (s:Sector {id: 990022}) MERGE (c)-[:HAS_SECTOR]->(s);
MATCH (s:Sector {id: 990021}), (a:Aisle {id: 990031}) MERGE (s)-[:HAS_AISLE]->(a);
MATCH (s:Sector {id: 990022}), (a:Aisle {id: 990032}) MERGE (s)-[:HAS_AISLE]->(a);
MATCH (a:Aisle {id: 990031}), (s:Shelf {id: 990041}) MERGE (a)-[:HAS_SHELF]->(s);
MATCH (a:Aisle {id: 990032}), (s:Shelf {id: 990042}) MERGE (a)-[:HAS_SHELF]->(s);

MATCH (c:Company {id: 990001}), (e:Employee {id: 990011}) MERGE (e)-[:WORKS_FOR]->(c);
MATCH (c:Company {id: 990001}), (e:Employee {id: 990012}) MERGE (e)-[:WORKS_FOR]->(c);
MATCH (c:Company {id: 990001}), (e:Employee {id: 990013}) MERGE (e)-[:WORKS_FOR]->(c);
MATCH (c:Company {id: 990002}), (e:Employee {id: 990014}) MERGE (e)-[:WORKS_FOR]->(c);
MATCH (c:Company {id: 990001}), (p:Product {id: 990051}) MERGE (p)-[:BELONGS_TO]->(c);
MATCH (c:Company {id: 990002}), (p:Product {id: 990052}) MERGE (p)-[:BELONGS_TO]->(c);

// Lucas cobre todo o corredor. Mariana cobre a prateleira diretamente.
MATCH (e:Employee {id: 990011}), (a:Aisle {id: 990031}) MERGE (e)-[:ASSIGNED_TO_AISLE]->(a);
MATCH (e:Employee {id: 990012}), (s:Shelf {id: 990041}) MERGE (e)-[:ASSIGNED_TO_SHELF]->(s);
MATCH (e:Employee {id: 990014}), (a:Aisle {id: 990032}) MERGE (e)-[:ASSIGNED_TO_AISLE]->(a);

MATCH (s:Shelf {id: 990041}), (p:Product {id: 990051}) MERGE (s)-[r:STOCKS]->(p) SET r.quantity = 8;
MATCH (s:Shelf {id: 990042}), (p:Product {id: 990052}) MERGE (s)-[r:STOCKS]->(p) SET r.quantity = 6;
MATCH (a:Alert {id: 990061}), (s:Shelf {id: 990041}) MERGE (a)-[:ON_SHELF]->(s);
MATCH (a:Alert {id: 990061}), (p:Product {id: 990051}) MERGE (a)-[:ABOUT_PRODUCT]->(p);
MATCH (a:Alert {id: 990062}), (s:Shelf {id: 990042}) MERGE (a)-[:ON_SHELF]->(s);
MATCH (a:Alert {id: 990062}), (p:Product {id: 990052}) MERGE (a)-[:ABOUT_PRODUCT]->(p);
