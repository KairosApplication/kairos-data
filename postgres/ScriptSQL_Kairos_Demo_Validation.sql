-- Somente leitura. Executar apos preparacao; salvar resultados antes de novas operacoes.
BEGIN READ ONLY;
SELECT reference_date, prepared_at, before_counts, after_counts,
       before_counts = after_counts AS counts_preserved FROM kairos_demo_date_runs;
SELECT r.reference_date, r.after_counts AS prepared_counts, n.current_counts,
       r.after_counts = n.current_counts AS unchanged_since_preparation
FROM kairos_demo_date_runs r CROSS JOIN (
    SELECT jsonb_build_object('purchases', (SELECT count(*) FROM Purchases),
        'restockings', (SELECT count(*) FROM Restockings),
        'alerts', (SELECT count(*) FROM Alerts),
        'purchase_products', (SELECT count(*) FROM Purchase_Products)) AS current_counts
) n;
SELECT 'purchases' AS source, count(*) AS rows, min(date) AS minimum, max(date) AS maximum
FROM Purchases
UNION ALL SELECT 'restockings', count(*), min(restocking_date), max(restocking_date) FROM Restockings
UNION ALL SELECT 'alerts', count(*), min(stockout_date)::timestamp, max(stockout_date)::timestamp FROM Alerts;

WITH dates AS (
    SELECT 'purchases' AS source, date::date AS day FROM Purchases
    UNION ALL SELECT 'restockings', restocking_date::date FROM Restockings
    UNION ALL SELECT 'alerts', stockout_date FROM Alerts
)
SELECT source, day, count(*) FROM dates GROUP BY source, day ORDER BY source, day;

-- Esperado: zero fora do historico imediatamente apos preparar.
-- Depois das demonstracoes, today_operations pode crescer; outside_window deve continuar zero.
WITH dates AS (
    SELECT 'purchases' AS source, date AS instant FROM Purchases
    UNION ALL SELECT 'restockings', restocking_date FROM Restockings
    UNION ALL SELECT 'alerts_open', stockout_date::timestamp FROM Alerts
    UNION ALL SELECT 'alerts_resolution', resolution_date FROM Alerts WHERE resolution_date IS NOT NULL
)
SELECT source,
    count(*) FILTER (WHERE instant IS NULL) AS null_dates,
    count(*) FILTER (WHERE instant < r.reference_date - 13 OR instant >= r.reference_date) AS outside_history,
    count(*) FILTER (WHERE instant >= r.reference_date AND instant < r.reference_date + 1) AS today_operations,
    count(*) FILTER (WHERE instant < w.start_date OR instant >= w.end_date_exclusive) AS outside_window,
    count(*) FILTER (WHERE instant > current_timestamp AT TIME ZONE 'America/Sao_Paulo') AS future_dates
FROM dates CROSS JOIN kairos_demo_date_runs r CROSS JOIN vw_bi_demo_window w
GROUP BY source;

SELECT * FROM vw_bi_sales_14d ORDER BY company_id, date_key;
SELECT * FROM vw_bi_restockings_14d ORDER BY company_id, date_key;
SELECT c.company_id, count(*) AS completed_purchases
FROM Purchases p JOIN Customers c ON c.id = p.customer_id CROSS JOIN vw_bi_demo_window w
WHERE p.status = 'COMPLETED' AND p.date >= w.start_date AND p.date < w.end_date_exclusive
GROUP BY c.company_id ORDER BY c.company_id;

-- Todos problems = 0. Complementar com ScriptSQL_Kairos_model_validation.sql.
SELECT 'alerts_chronology' AS check_name, count(*) AS problems FROM Alerts
WHERE resolution_date < stockout_date::timestamp OR (status = 'RESOLVED' AND resolution_date IS NULL)
UNION ALL
SELECT 'restocking_shelf_company', count(*) FROM Restockings r
JOIN Employees e ON e.id = r.employee_id JOIN Shelves sh ON sh.id = r.shelf_id
JOIN Aisles a ON a.id = sh.aisle_id JOIN Sectors s ON s.id = a.sector_id
WHERE e.company_id <> s.company_id
UNION ALL
SELECT 'alerts_company', count(*) FROM Alerts al
JOIN Shelves sh ON sh.id = al.shelf_id JOIN Aisles a ON a.id = sh.aisle_id
JOIN Sectors s ON s.id = a.sector_id
LEFT JOIN Employees e ON e.id = al.employee_id LEFT JOIN Products p ON p.id = al.product_id
WHERE e.company_id <> s.company_id OR p.company_id <> s.company_id
UNION ALL
SELECT 'damaged_exceeds_restocked', count(*) FROM Restockings WHERE qnt_avarias > restocked_quantity;
COMMIT;
