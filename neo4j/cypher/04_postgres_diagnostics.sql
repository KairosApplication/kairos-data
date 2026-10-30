-- Rode NO POSTGRESQL, nao no Neo4j.
-- Checa as relacoes do dataload; nao altera nenhum dado.

SELECT 'employee_aisles_cross_company' AS verificacao, COUNT(*) AS problemas
FROM Employee_Aisles ea
JOIN Employees e ON e.id = ea.employee_id
JOIN Aisles a ON a.id = ea.aisle_id
JOIN Sectors s ON s.id = a.sector_id
WHERE e.company_id <> s.company_id
UNION ALL
SELECT 'shelf_employees_cross_company', COUNT(*)
FROM Shelf_Employees se
JOIN Employees e ON e.id = se.employee_id
JOIN Shelves sh ON sh.id = se.shelf_id
JOIN Aisles a ON a.id = sh.aisle_id
JOIN Sectors s ON s.id = a.sector_id
WHERE e.company_id <> s.company_id
UNION ALL
SELECT 'product_shelves_cross_company', COUNT(*)
FROM Product_Shelves ps
JOIN Products p ON p.id = ps.product_id
JOIN Shelves sh ON sh.id = ps.shelf_id
JOIN Aisles a ON a.id = sh.aisle_id
JOIN Sectors s ON s.id = a.sector_id
WHERE p.company_id <> s.company_id
UNION ALL
SELECT 'alerts_cross_company', COUNT(*)
FROM Alerts al
JOIN Products p ON p.id = al.product_id
JOIN Shelves sh ON sh.id = al.shelf_id
JOIN Aisles a ON a.id = sh.aisle_id
JOIN Sectors s ON s.id = a.sector_id
WHERE p.company_id <> s.company_id;
