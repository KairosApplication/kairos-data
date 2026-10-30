-- ============================================================
-- KAIROS - EVIDENCIA DE DESEMPENHO
-- ============================================================
-- SOMENTE NO BANCO LOCAL RESTAURADO
--
-- Nao executar na Aiven.
-- Este script remove indices temporariamente dentro de uma
-- transacao para comparar desempenho e depois faz ROLLBACK.
--
-- Banco de teste: kairos_restore (Docker)
-- ============================================================

-- ============================================================
-- VERIFICACAO DO AMBIENTE
-- ============================================================

SELECT
    current_database() AS banco,
    version() AS versao;

-- ============================================================
-- INDICES EXISTENTES
-- ============================================================

SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
      'idx_restockings_employee_date',
      'idx_alerts_open_employee_date',
      'idx_product_inventories_product'
  )
ORDER BY indexname;

-- ============================================================
-- ANTES DOS INDICES (AMBIENTE LOCAL)
-- ============================================================

BEGIN;

DROP INDEX IF EXISTS public.idx_restockings_employee_date;
DROP INDEX IF EXISTS public.idx_alerts_open_employee_date;
DROP INDEX IF EXISTS public.idx_product_inventories_product;

-- Consulta 1: Historico de reposicoes

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    r.id,
    r.employee_id,
    r.product_id,
    r.restocking_date
FROM Restockings r
WHERE r.employee_id = 1
ORDER BY r.restocking_date DESC
LIMIT 25;

-- Consulta 2: Alertas abertos

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    a.id,
    a.employee_id,
    a.shelf_id,
    a.stockout_date
FROM Alerts a
WHERE a.employee_id = 1
  AND a.status = 'OPEN'
ORDER BY a.stockout_date DESC
LIMIT 25;

-- Consulta 3: Produtos em estoque

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    pi.inventory_id,
    pi.product_id,
    pi.product_quantity
FROM Product_Inventories pi
WHERE pi.product_id = 1;

-- Desfaz a remocao temporaria dos indices

ROLLBACK;

-- ============================================================
-- DEPOIS DOS INDICES (ESTADO RESTAURADO)
-- ============================================================

-- Consulta 1: Historico de reposicoes

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    r.id,
    r.employee_id,
    r.product_id,
    r.restocking_date
FROM Restockings r
WHERE r.employee_id = 1
ORDER BY r.restocking_date DESC
LIMIT 25;

-- Consulta 2: Alertas abertos

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    a.id,
    a.employee_id,
    a.shelf_id,
    a.stockout_date
FROM Alerts a
WHERE a.employee_id = 1
  AND a.status = 'OPEN'
ORDER BY a.stockout_date DESC
LIMIT 25;

-- Consulta 3: Produtos em estoque

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    pi.inventory_id,
    pi.product_id,
    pi.product_quantity
FROM Product_Inventories pi
WHERE pi.product_id = 1;

-- ============================================================
-- CONFERENCIA FINAL: INDICES PRESERVADOS
-- ============================================================

SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
      'idx_restockings_employee_date',
      'idx_alerts_open_employee_date',
      'idx_product_inventories_product'
  )
ORDER BY indexname;