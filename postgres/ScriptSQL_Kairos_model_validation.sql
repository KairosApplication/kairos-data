-- ==============================================================
-- KAIROS | 09 - VALIDACAO NAO DESTRUTIVA DO MODELO
-- Todas as consultas sao somente leitura.
-- Zero nos checks de incoerencia entre empresas = esperado.
-- A certificacao formal de 3FN ainda demanda revisar dependencias.
-- ==============================================================

-- Contagem por tabela (evidencia da massa de dados carregada).
SELECT 'companies' AS table_name, COUNT(*) AS row_count FROM Companies
UNION ALL SELECT 'users', COUNT(*) FROM Users
UNION ALL SELECT 'employees', COUNT(*) FROM Employees
UNION ALL SELECT 'products', COUNT(*) FROM Products
UNION ALL SELECT 'restockings', COUNT(*) FROM Restockings
UNION ALL SELECT 'purchases', COUNT(*) FROM Purchases
ORDER BY table_name;

-- Cargos validos.
SELECT position, COUNT(*) AS employees_count
FROM Employees GROUP BY position ORDER BY position;

-- FKs isoladas nao garantem que as linhas relacionadas sejam da mesma empresa.
SELECT 'inventory_vs_sector' AS check_name, COUNT(*)::BIGINT AS problems
FROM Inventories i
JOIN Sectors s ON s.id = i.sector_id
WHERE i.company_id <> s.company_id

UNION ALL
SELECT 'product_vs_category', COUNT(*)
FROM Products p
JOIN Categories c ON c.id = p.category_id
WHERE p.company_id <> c.company_id

UNION ALL
SELECT 'product_inventory_vs_inventory', COUNT(*)
FROM Product_Inventories pi
JOIN Products p ON p.id = pi.product_id
JOIN Inventories i ON i.id = pi.inventory_id
WHERE p.company_id <> i.company_id

UNION ALL
SELECT 'product_shelf_vs_sector', COUNT(*)
FROM Product_Shelves ps
JOIN Products p ON p.id = ps.product_id
JOIN Shelves sh ON sh.id = ps.shelf_id
JOIN Aisles a ON a.id = sh.aisle_id
JOIN Sectors s ON s.id = a.sector_id
WHERE p.company_id <> s.company_id

UNION ALL
SELECT 'employee_aisle_vs_sector', COUNT(*)
FROM Employee_Aisles ea
JOIN Employees e ON e.id = ea.employee_id
JOIN Aisles a ON a.id = ea.aisle_id
JOIN Sectors s ON s.id = a.sector_id
WHERE e.company_id <> s.company_id

UNION ALL
SELECT 'restocking_vs_employee_company', COUNT(*)
FROM Restockings r
JOIN Employees e ON e.id = r.employee_id
JOIN Products p ON p.id = r.product_id
JOIN Inventories i ON i.id = r.inventory_id
WHERE e.company_id <> p.company_id OR e.company_id <> i.company_id

UNION ALL
SELECT 'purchase_item_vs_customer_company', COUNT(*)
FROM Purchase_Products pp
JOIN Purchases pu ON pu.id = pp.purchase_id
JOIN Customers c ON c.id = pu.customer_id
JOIN Products p ON p.id = pp.product_id
WHERE c.company_id <> p.company_id;

-- Ver cardinalidade tecnica (FKs de todas as tabelas).
SELECT tc.table_name AS child_table, kcu.column_name AS fk_column,
       ccu.table_name AS parent_table, ccu.column_name AS parent_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON kcu.constraint_name = tc.constraint_name
 AND kcu.table_schema = tc.table_schema
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
 AND ccu.table_schema = tc.table_schema
WHERE tc.table_schema = 'public' AND tc.constraint_type = 'FOREIGN KEY'
ORDER BY child_table, fk_column;

-- Observacao de modelagem: Inventories.company_id e potencialmente
-- derivavel de sector_id quando setor existe. Avaliar dependencia
-- funcional e politica para inventories.sector_id NULL antes de
-- declarar formalmente que todas as tabelas estao em 3FN.
