-- ==============================================================
-- KAIROS | 05 - ANALISE DE DESEMPENHO E INDICES
-- Executar APOS a carga inicial. Reexecutavel (IF NOT EXISTS).
-- EXPLAIN ANALYZE realmente executa cada SELECT (somente leitura).
-- Guarde os planos ANTES e DEPOIS para o relatorio da disciplina.
-- ==============================================================

-- BASELINE: copie o plano, Execution Time, Buffers e scan utilizado.
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.employee_id, r.product_id, r.restocking_date
FROM Restockings r
WHERE r.employee_id = 1
ORDER BY r.restocking_date DESC
LIMIT 25;

EXPLAIN (ANALYZE, BUFFERS)
SELECT a.id, a.employee_id, a.shelf_id, a.stockout_date
FROM Alerts a
WHERE a.employee_id = 1 AND a.status = 'OPEN'
ORDER BY a.stockout_date DESC
LIMIT 25;

EXPLAIN (ANALYZE, BUFFERS)
SELECT pi.inventory_id, pi.product_id, pi.product_quantity
FROM Product_Inventories pi
WHERE pi.product_id = 1;

-- Os índices UNIQUE existentes ja cobrem outros acessos. Evitar duplicatas.
CREATE INDEX IF NOT EXISTS idx_restockings_employee_date
    ON Restockings (employee_id, restocking_date DESC);

CREATE INDEX IF NOT EXISTS idx_alerts_open_employee_date
    ON Alerts (employee_id, stockout_date DESC)
    WHERE status = 'OPEN';

-- O UNIQUE de Product_Inventories e (inventory_id, product_id),
-- e nao substitui este indice para buscas iniciadas por product_id.
CREATE INDEX IF NOT EXISTS idx_product_inventories_product
    ON Product_Inventories (product_id);

CREATE INDEX IF NOT EXISTS idx_purchases_customer_date
    ON Purchases (customer_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_employees_company_position
    ON Employees (company_id, position);

-- Atualizar estatisticas para o planejador avaliar os novos indices.
ANALYZE Restockings;
ANALYZE Alerts;
ANALYZE Product_Inventories;
ANALYZE Purchases;
ANALYZE Employees;

-- POS-OTIMIZACAO: mesmos SELECTs e filtros do baseline.
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.employee_id, r.product_id, r.restocking_date
FROM Restockings r
WHERE r.employee_id = 1
ORDER BY r.restocking_date DESC
LIMIT 25;

EXPLAIN (ANALYZE, BUFFERS)
SELECT a.id, a.employee_id, a.shelf_id, a.stockout_date
FROM Alerts a
WHERE a.employee_id = 1 AND a.status = 'OPEN'
ORDER BY a.stockout_date DESC
LIMIT 25;

EXPLAIN (ANALYZE, BUFFERS)
SELECT pi.inventory_id, pi.product_id, pi.product_quantity
FROM Product_Inventories pi
WHERE pi.product_id = 1;

-- Evidencia dos indices criados (somente leitura).
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;

-- OBS: index scan nao e obrigatoriamente mais rapido em tabelas pequenas;
-- registre tempos reais e compare varias execucoes (cache influencia).
