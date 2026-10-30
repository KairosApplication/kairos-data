-- ==============================================================
-- KAIROS | 04 - DATA MART LOGICO (STAR SCHEMA EM VIEWS)
-- Base do BI para alinhamento com Dani: views dim_* e fact_*.
-- As dimensoes/fatos sao VIRTUAIS, sem duplicar fisicamente dados.
-- Usa CTEs e Window Functions nos indicadores.
-- Uma ferramenta JDBC ou conector PostgreSQL pode ler essas views.
-- IMPORTANTE: as consultas devem filtrar company_id por permissao.
-- ==============================================================

-- Dimensao empresa.
CREATE OR REPLACE VIEW vw_bi_dim_company AS
SELECT c.id AS company_id, c.name AS company_name, c.plan
FROM Companies c;

-- Dimensao colaborador sem dados pessoais sensiveis.
CREATE OR REPLACE VIEW vw_bi_dim_employee AS
SELECT e.id AS employee_id, e.company_id, e.position
FROM Employees e;

-- Dimensao produto; evita categorias de outra empresa.
CREATE OR REPLACE VIEW vw_bi_dim_product AS
SELECT p.id AS product_id, p.company_id, p.name AS product_name,
       p.brand, p.category_id, cat.category AS category_name
FROM Products p
LEFT JOIN Categories cat
  ON cat.id = p.category_id AND cat.company_id = p.company_id;

-- Dimensao data com datas usadas nas duas tabelas de fatos.
CREATE OR REPLACE VIEW vw_bi_dim_date AS
WITH dates AS (
    SELECT restocking_date::DATE AS date_key FROM Restockings
    UNION
    SELECT date::DATE AS date_key FROM Purchases
)
SELECT date_key,
       EXTRACT(YEAR FROM date_key)::INT AS year_number,
       EXTRACT(MONTH FROM date_key)::INT AS month_number,
       EXTRACT(QUARTER FROM date_key)::INT AS quarter_number,
       EXTRACT(WEEK FROM date_key)::INT AS week_number
FROM dates
WHERE date_key IS NOT NULL;

-- Fato reposicoes (grain: UMA reposicao).
CREATE OR REPLACE VIEW vw_bi_fact_restocking AS
SELECT r.id AS restocking_id,
       e.company_id,
       r.employee_id,
       r.product_id,
       r.shelf_id,
       r.inventory_id,
       r.restocking_date::DATE AS date_key,
       r.restocking_date,
       r.restocked_quantity,
       r.qnt_avarias,
       (r.restocked_quantity - r.qnt_avarias) AS sellable_quantity
FROM Restockings r
JOIN Employees e ON e.id = r.employee_id
JOIN Products p ON p.id = r.product_id AND p.company_id = e.company_id
JOIN Inventories inv ON inv.id = r.inventory_id AND inv.company_id = e.company_id;

-- Fato vendas (grain: UM item de compra).
CREATE OR REPLACE VIEW vw_bi_fact_sale_item AS
SELECT pp.id AS purchase_item_id,
       pu.id AS purchase_id,
       cu.company_id,
       cu.id AS customer_id,
       pp.product_id,
       pu.date::DATE AS date_key,
       pu.status,
       pp.quantity,
       pp.amount::NUMERIC AS unit_price,
       (pp.amount::NUMERIC * pp.quantity) AS item_total
FROM Purchase_Products pp
JOIN Purchases pu ON pu.id = pp.purchase_id
JOIN Customers cu ON cu.id = pu.customer_id
JOIN Products p ON p.id = pp.product_id AND p.company_id = cu.company_id;

-- Indicadores semanais por repositor: CTE + RANK + SUM OVER.
CREATE OR REPLACE VIEW vw_bi_weekly_stockers AS
WITH base AS (
    SELECT company_id,
           employee_id,
           DATE_TRUNC('week', restocking_date)::DATE AS week_start,
           restocked_quantity,
           qnt_avarias,
           sellable_quantity
    FROM vw_bi_fact_restocking
), grouped AS (
    SELECT company_id, employee_id, week_start,
           COUNT(*)::BIGINT AS total_operations,
           SUM(restocked_quantity)::BIGINT AS total_restocked,
           SUM(qnt_avarias)::BIGINT AS total_damaged,
           SUM(sellable_quantity)::BIGINT AS total_sellable
    FROM base
    GROUP BY company_id, employee_id, week_start
)
SELECT company_id, employee_id, week_start,
       total_operations, total_restocked, total_damaged, total_sellable,
       RANK() OVER (
           PARTITION BY company_id, week_start
           ORDER BY total_sellable DESC
       ) AS position_in_company_week,
       SUM(total_sellable) OVER (
           PARTITION BY company_id, employee_id
           ORDER BY week_start
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS employee_running_total
FROM grouped;

-- Receita mensal + acumulado de vendas finalizadas.
CREATE OR REPLACE VIEW vw_bi_monthly_sales AS
WITH monthly AS (
    SELECT company_id,
           DATE_TRUNC('month', date_key)::DATE AS month_start,
           SUM(item_total)::NUMERIC(18,2) AS revenue,
           SUM(quantity)::BIGINT AS units_sold,
           COUNT(DISTINCT purchase_id)::BIGINT AS purchases_count
    FROM vw_bi_fact_sale_item
    WHERE status = 'COMPLETED' AND date_key IS NOT NULL
    GROUP BY company_id, DATE_TRUNC('month', date_key)::DATE
)
SELECT company_id, month_start, revenue, units_sold, purchases_count,
       SUM(revenue) OVER (
           PARTITION BY company_id ORDER BY month_start
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_revenue
FROM monthly;

-- Exemplos de teste (leitura e dados apenas da empresa 1).
SELECT * FROM vw_bi_weekly_stockers
WHERE company_id = 1
ORDER BY week_start DESC, position_in_company_week
LIMIT 20;

SELECT * FROM vw_bi_monthly_sales
WHERE company_id = 1
ORDER BY month_start DESC
LIMIT 20;

-- OBS: apenas possuir company_id na view NAO garante isolamento.
-- Aplicar filtros e autorizacao no backend/BI (ou RLS/roles dedicados).
