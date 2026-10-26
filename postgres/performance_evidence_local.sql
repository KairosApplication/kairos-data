-- KAIROS — Evidência de desempenho (SOMENTE NO BANCO LOCAL RESTAURADO)
-- Não executar este script na Aiven: ele remove índices TEMPORARIAMENTE
-- na transação local para coletar baseline e depois faz ROLLBACK.
-- Executar no PostgreSQL de teste `kairos_restore` (Docker).
-- Saída pode variar com cache, estatísticas e volume de dados.

\echo '===== VERIFICACAO DO AMBIENTE ====='
SELECT current_database() AS banco, version() AS versao;

\echo '===== INDICES EXISTENTES ====='
SELECT indexname FROM pg_indexes WHERE schemaname='public'
 AND indexname IN ('idx_restockings_employee_date','idx_alerts_open_employee_date','idx_product_inventories_product')
 ORDER BY indexname;

-- Baseline sem estes três índices, reversível via ROLLBACK.
BEGIN;
DROP INDEX IF EXISTS public.idx_restockings_employee_date;
DROP INDEX IF EXISTS public.idx_alerts_open_employee_date;
DROP INDEX IF EXISTS public.idx_product_inventories_product;

\echo '===== ANTES DOS INDICES (ambiente local) ====='
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.employee_id, r.product_id, r.restocking_date
FROM Restockings r
WHERE r.employee_id = 1
ORDER BY r.restocking_date DESC
LIMIT 25;

EXPLAIN (ANALYZE, BUFFERS)
SELECT a.id, a.employee_id, a.shelf_id, a.stockout_date
FROM Alerts a
WHERE a.employee_id = 1 AND a.status='OPEN'
ORDER BY a.stockout_date DESC
LIMIT 25;

EXPLAIN (ANALYZE, BUFFERS)
SELECT pi.inventory_id, pi.product_id, pi.product_quantity
FROM Product_Inventories pi
WHERE pi.product_id=1;

ROLLBACK;

\echo '===== DEPOIS DOS INDICES (estado restaurado) ====='
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.id, r.employee_id, r.product_id, r.restocking_date
FROM Restockings r
WHERE r.employee_id = 1
ORDER BY r.restocking_date DESC
LIMIT 25;

EXPLAIN (ANALYZE, BUFFERS)
SELECT a.id, a.employee_id, a.shelf_id, a.stockout_date
FROM Alerts a
WHERE a.employee_id = 1 AND a.status='OPEN'
ORDER BY a.stockout_date DESC
LIMIT 25;

EXPLAIN (ANALYZE, BUFFERS)
SELECT pi.inventory_id, pi.product_id, pi.product_quantity
FROM Product_Inventories pi
WHERE pi.product_id=1;

\echo '===== CONFERENCIA: indices permanecem criados ====='
SELECT indexname FROM pg_indexes WHERE schemaname='public'
 AND indexname IN ('idx_restockings_employee_date','idx_alerts_open_employee_date','idx_product_inventories_product')
 ORDER BY indexname;
