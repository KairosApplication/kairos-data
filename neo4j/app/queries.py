# Recebe company_id do backend. Este servico nao verifica usuario final; o backend deve autorizar acesso.
ALERT_CANDIDATES = """
MATCH (alert:Alert {id: $alert_id, company_id: $company_id})
      -[:ON_SHELF]->(s:Shelf {company_id: $company_id})
      <-[:HAS_SHELF]-(a:Aisle {company_id: $company_id})
MATCH (e:Employee {company_id: $company_id, position: 'STOCKER'})
WHERE EXISTS { MATCH (e)-[:ASSIGNED_TO_AISLE]->(a) }
   OR EXISTS { MATCH (e)-[:ASSIGNED_TO_SHELF]->(s) }
RETURN DISTINCT e.id AS employee_id, e.name AS name,
       CASE WHEN EXISTS { MATCH (e)-[:ASSIGNED_TO_SHELF]->(s) } THEN 'SHELF' ELSE 'AISLE' END AS assignment
ORDER BY assignment DESC, name
"""

AISLE_STOCKERS = """
MATCH (a:Aisle {id: $aisle_id, company_id: $company_id})
MATCH (e:Employee {company_id: $company_id, position: 'STOCKER'})
WHERE EXISTS { MATCH (e)-[:ASSIGNED_TO_AISLE]->(a) }
   OR EXISTS { MATCH (a)-[:HAS_SHELF]->(s:Shelf)<-[:ASSIGNED_TO_SHELF]-(e) }
RETURN DISTINCT e.id AS employee_id, e.name AS name
ORDER BY name
"""

EMPLOYEE_COVERAGE = """
MATCH (e:Employee {id: $employee_id, company_id: $company_id, position: 'STOCKER'})
MATCH (e)-[:ASSIGNED_TO_AISLE]->(a:Aisle {company_id: $company_id})
      <-[:HAS_AISLE]-(s:Sector {company_id: $company_id})
RETURN a.id AS aisle_id, a.position AS aisle_position,
       s.id AS sector_id, s.name AS sector_name
ORDER BY sector_name, aisle_position
"""
