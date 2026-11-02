-- Executar apos ScriptSQL_Kairos_bi_views.sql na copia demo.
-- Views virtuais; periodo recalculado em cada consulta, independente do fuso da sessao.
CREATE OR REPLACE VIEW vw_bi_demo_window AS
SELECT today - 13 AS start_date, today + 1 AS end_date_exclusive
FROM (SELECT (current_timestamp AT TIME ZONE 'America/Sao_Paulo')::date AS today) d;

-- Grain: empresa/dia. Contagem de compras vem do cabecalho, sem duplicar por item.
CREATE OR REPLACE VIEW vw_bi_sales_14d AS
WITH sales AS (
    SELECT c.company_id, p.id, p.date::date AS date_key
    FROM Purchases p JOIN Customers c ON c.id = p.customer_id
    CROSS JOIN vw_bi_demo_window w
    WHERE p.status = 'COMPLETED'
      AND p.date >= w.start_date::timestamp AND p.date < w.end_date_exclusive::timestamp
), items AS (
    SELECT purchase_id, company_id, sum(item_total) AS revenue, sum(quantity) AS units_sold
    FROM vw_bi_fact_sale_item WHERE status = 'COMPLETED'
    GROUP BY purchase_id, company_id
)
SELECT s.company_id, s.date_key, count(*) AS purchases_count,
       coalesce(sum(i.revenue), 0)::numeric(18,2) AS revenue,
       coalesce(sum(i.units_sold), 0)::bigint AS units_sold,
       count(*) FILTER (WHERE i.purchase_id IS NULL) AS purchases_without_items
FROM sales s LEFT JOIN items i ON i.purchase_id = s.id AND i.company_id = s.company_id
GROUP BY s.company_id, s.date_key;

CREATE OR REPLACE VIEW vw_bi_restockings_14d AS
SELECT r.company_id, r.date_key, count(*) AS total_operations,
       sum(r.restocked_quantity)::bigint AS total_restocked,
       sum(r.qnt_avarias)::bigint AS total_damaged,
       sum(r.sellable_quantity)::bigint AS total_sellable
FROM vw_bi_fact_restocking r CROSS JOIN vw_bi_demo_window w
WHERE r.restocking_date >= w.start_date::timestamp
  AND r.restocking_date < w.end_date_exclusive::timestamp
GROUP BY r.company_id, r.date_key;
-- company_id e chave de agrupamento, NAO autorizacao. Aplicar RLS no BI/backend.
