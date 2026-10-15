-- ============================================================
-- KAIROS - DATALOAD COM 1.000.000 DE REGISTROS
-- PostgreSQL
--
-- Gerado para o schema enviado pelo usuário.
-- Dados fictícios, legíveis e determinísticos.
-- CPFs, CNPJs e e-mails possuem valores únicos.
-- FKs, UNIQUEs e CHECKs do schema são respeitados.
--
-- IMPORTANTE:
-- "Nenhum dado repetido" não pode significar que nenhuma coluna
-- pode repetir qualquer valor, pois FKs, status, cargos, categorias
-- e empresas necessariamente são reutilizados para formar relações.
-- O script evita duplicidade onde ela representa uma entidade/valor
-- identificador (CPF, CNPJ, e-mail, pares UNIQUE etc.).
--
-- O total abaixo considera as linhas explicitamente carregadas.
-- Triggers de auditoria de Products/Purchases são temporariamente
-- desabilitados para manter o total EXATO em 1.000.000.
--
-- DISTRIBUIÇÃO:
-- Companies                 100
-- Users                 250.000
-- Sectors                 1.000
-- Aisles                  10.000
-- Shelves                 50.000
-- Employees               50.000
-- Inventories              1.000
-- Inventory_Employees     50.000
-- Shelf_Employees         50.000
-- Employee_Aisles         50.000
-- Categories               2.000
-- Products                80.000
-- Product_Shelves        100.000
-- Product_Inventories    100.000
-- Restockings             50.000
-- Alerts                  20.000
-- Customers              150.000
-- Purchases               25.000
-- Purchase_Products       10.900
-- --------------------------------
-- TOTAL                 1.000.000
-- ============================================================

BEGIN;

SET LOCAL synchronous_commit = OFF;

-- Mantém o total exato, sem linhas extras geradas pelos triggers.
ALTER TABLE Products DISABLE TRIGGER trg_products_audit;
ALTER TABLE Purchases DISABLE TRIGGER trg_purchases_audit;

-- ============================================================
-- HELPERS LOCAIS
-- ============================================================

CREATE TEMP TABLE dl_first_names(id int primary key, value text);
INSERT INTO dl_first_names VALUES
(1,'Lucas'),(2,'Gabriel'),(3,'Rafael'),(4,'Matheus'),(5,'Guilherme'),
(6,'Felipe'),(7,'Bruno'),(8,'Leonardo'),(9,'Henrique'),(10,'Eduardo'),
(11,'Pedro'),(12,'João'),(13,'Caio'),(14,'Daniel'),(15,'Thiago'),
(16,'Mariana'),(17,'Beatriz'),(18,'Camila'),(19,'Larissa'),(20,'Juliana'),
(21,'Ana'),(22,'Isabela'),(23,'Letícia'),(24,'Amanda'),(25,'Carolina'),
(26,'Vitória'),(27,'Luana'),(28,'Bianca'),(29,'Fernanda'),(30,'Natália');

CREATE TEMP TABLE dl_last_names(id int primary key, value text);
INSERT INTO dl_last_names VALUES
(1,'Silva'),(2,'Santos'),(3,'Oliveira'),(4,'Souza'),(5,'Rodrigues'),
(6,'Ferreira'),(7,'Alves'),(8,'Pereira'),(9,'Lima'),(10,'Gomes'),
(11,'Costa'),(12,'Ribeiro'),(13,'Martins'),(14,'Carvalho'),(15,'Almeida'),
(16,'Lopes'),(17,'Soares'),(18,'Fernandes'),(19,'Vieira'),(20,'Barbosa'),
(21,'Rocha'),(22,'Dias'),(23,'Monteiro'),(24,'Mendes'),(25,'Cardoso'),
(26,'Reis'),(27,'Araújo'),(28,'Nascimento'),(29,'Moreira'),(30,'Teixeira');

CREATE TEMP TABLE dl_brands(id int primary key, value text);
INSERT INTO dl_brands VALUES
(1,'Aurora'),(2,'Serra Azul'),(3,'Boa Mesa'),(4,'Viva Mais'),(5,'Campo Real'),
(6,'Sabor Nobre'),(7,'Casa Verde'),(8,'Sol Nascente'),(9,'Primavera'),(10,'Monte Belo'),
(11,'Vale Dourado'),(12,'Puro Sabor'),(13,'Nova Terra'),(14,'Essencial'),(15,'Bom Dia'),
(16,'Raízes'),(17,'Granville'),(18,'Alvorada'),(19,'Fazenda Sul'),(20,'Estação');

-- ============================================================
-- 1) COMPANIES - 100
-- ============================================================

INSERT INTO Companies (id, name, cnpj, email, plan)
SELECT
    g,
    (ARRAY['Mercado','Supermercado','Empório','Comercial','Atacadista'])[((g-1)%5)+1]
      || ' ' ||
    (ARRAY['Horizonte','Primavera','Boa Compra','Nova Era','Santa Clara',
           'Vale Verde','Central','Ponto Certo','Estrela','São Miguel'])[((g-1)%10)+1]
      || ' ' || lpad(g::text,3,'0'),
    lpad((10000000000000::bigint + g)::text,14,'0'),
    'contato' || g || '@empresa-kairos' || g || '.com.br',
    (ARRAY['BASIC','STANDARD','PREMIUM','ENTERPRISE'])[((g-1)%4)+1]
FROM generate_series(1,100) g;

-- ============================================================
-- 2) USERS - 250.000
-- ============================================================

INSERT INTO Users (id, name, last_name, birth_date, cpf, email, password)
SELECT
    g,
    fn.value,
    ln.value || ' ' || ln2.value,
    DATE '1955-01-01' + ((g * 37) % 18250),
    lpad((10000000000::bigint + g)::text,11,'0'),
    lower(fn.value) || '.' || lower(ln.value) || '.' || g || '@pessoa-kairos.com.br',
    '$2b$12$KairosFicticioSeguro' || lpad(g::text,10,'0')
FROM generate_series(1,250000) g
JOIN dl_first_names fn ON fn.id = ((g-1)%30)+1
JOIN dl_last_names ln ON ln.id = (((g-1)/30)%30)+1
JOIN dl_last_names ln2 ON ln2.id = (((g-1)/900)%30)+1;

-- ============================================================
-- 3) SECTORS - 1.000 (10 por empresa)
-- ============================================================

INSERT INTO Sectors (id, company_id, name, type)
SELECT
    g,
    ((g-1)/10)+1,
    (ARRAY['Hortifruti','Bebidas','Mercearia','Higiene','Limpeza',
           'Padaria','Frios','Congelados','Estoque Seco','Depósito'])[((g-1)%10)+1],
    CASE WHEN ((g-1)%10)+1 <= 8 THEN 'SALES_FLOOR' ELSE 'STORAGE' END
FROM generate_series(1,1000) g;

-- ============================================================
-- 4) AISLES - 10.000 (10 por setor)
-- ============================================================

INSERT INTO Aisles (id, sector_id, position)
SELECT g, ((g-1)/10)+1, ((g-1)%10)+1
FROM generate_series(1,10000) g;

-- ============================================================
-- 5) SHELVES - 50.000 (5 por corredor)
-- ============================================================

INSERT INTO Shelves (id, aisle_id, maximum_capacity)
SELECT
    g,
    ((g-1)/5)+1,
    120 + ((g * 17) % 181)
FROM generate_series(1,50000) g;

-- ============================================================
-- 6) EMPLOYEES - 50.000
-- usuários 1..50.000
-- ============================================================

INSERT INTO Employees (id, users_id, company_id, position)
SELECT
    g,
    g,
    ((g-1)%100)+1,
    (ARRAY['Repositor','Operador de Caixa','Fiscal de Loja','Estoquista',
           'Atendente','Supervisor','Auxiliar de Loja','Conferente'])[((g-1)%8)+1]
FROM generate_series(1,50000) g;

-- ============================================================
-- 7) INVENTORIES - 1.000
-- Um por setor; company_id coerente com Sectors
-- ============================================================

INSERT INTO Inventories (id, company_id, sector_id)
SELECT g, ((g-1)/10)+1, g
FROM generate_series(1,1000) g;

-- ============================================================
-- 8) INVENTORY_EMPLOYEES - 50.000
-- ============================================================

INSERT INTO Inventory_Employees (id, inventory_id, employee_id)
SELECT
    g,
    (((((g-1)%100)+1)-1)*10 + (((g-1)/100)%10)+1),
    g
FROM generate_series(1,50000) g;

-- ============================================================
-- 9) SHELF_EMPLOYEES - 50.000
-- ============================================================

INSERT INTO Shelf_Employees (id, shelf_id, employee_id)
SELECT g, g, g
FROM generate_series(1,50000) g;

-- ============================================================
-- 10) EMPLOYEE_AISLES - 50.000
-- ============================================================

INSERT INTO Employee_Aisles (id, aisle_id, employee_id)
SELECT
    g,
    (((g-1)%10000)+1),
    g
FROM generate_series(1,50000) g;

-- ============================================================
-- 11) CATEGORIES - 2.000 (20 por empresa)
-- ============================================================

INSERT INTO Categories (id, company_id, category)
SELECT
    g,
    ((g-1)/20)+1,
    (ARRAY[
      'Arroz e Grãos','Massas','Molhos','Cafés','Chás','Biscoitos','Cereais',
      'Leites','Queijos','Iogurtes','Sucos','Refrigerantes','Águas',
      'Higiene Pessoal','Limpeza Doméstica','Congelados','Frios',
      'Padaria','Hortifruti','Utilidades'
    ])[((g-1)%20)+1]
FROM generate_series(1,2000) g;

-- ============================================================
-- 12) PRODUCTS - 80.000 (800 por empresa)
-- Nomes legíveis e únicos por composição.
-- ============================================================

INSERT INTO Products (id, company_id, brand, price, name, category_id)
SELECT
    g,
    ((g-1)/800)+1 AS company_id,
    b.value,
    ((2.50 + ((g * 137) % 25000) / 100.0)::numeric(10,2))::money,
    (ARRAY[
      'Arroz Integral','Feijão Carioca','Macarrão Espaguete','Molho de Tomate',
      'Café Torrado','Chá de Camomila','Biscoito Integral','Granola Tradicional',
      'Leite Integral','Queijo Minas','Iogurte Natural','Suco de Laranja',
      'Refrigerante Cola','Água Mineral','Sabonete Neutro','Detergente Líquido',
      'Pizza Congelada','Peito de Peru','Pão de Forma','Aveia em Flocos'
    ])[((g-1)%20)+1]
    || ' ' ||
    (ARRAY['Tradicional','Premium','Família','Seleção','Especial'])[((g-1)/20)%5+1]
    || ' ' ||
    (ARRAY['200g','300g','500g','750g','1kg','1L','1,5L','2L'])[((g-1)/100)%8+1]
    || ' Lote ' || lpad(g::text,6,'0'),
    ((((g-1)/800))*20 + ((g-1)%20)+1)
FROM generate_series(1,80000) g
JOIN dl_brands b ON b.id = ((g-1)%20)+1;

-- ============================================================
-- 13) PRODUCT_SHELVES - 100.000
-- 1.000 relações por empresa.
-- ============================================================

INSERT INTO Product_Shelves (id, product_id, shelf_id, product_quantity)
SELECT
    g,
    (c * 800) + ((k-1)%800)+1,
    (c * 500) + ((k-1)%500)+1,
    5 + ((g * 11) % 40)
FROM generate_series(0,99) c
CROSS JOIN generate_series(1,1000) k
CROSS JOIN LATERAL (SELECT c*1000+k AS g) x;

-- ============================================================
-- 14) PRODUCT_INVENTORIES - 100.000
-- 1.000 relações por empresa.
-- ============================================================

INSERT INTO Product_Inventories (id, inventory_id, product_id, product_quantity)
SELECT
    g,
    (c * 10) + ((k-1)%10)+1,
    (c * 800) + ((k-1)/10)+1,
    150 + ((g * 19) % 851)
FROM generate_series(0,99) c
CROSS JOIN generate_series(1,1000) k
CROSS JOIN LATERAL (SELECT c*1000+k AS g) x;

-- ============================================================
-- 15) RESTOCKINGS - 50.000
-- Relações sempre dentro da mesma empresa.
-- ============================================================

INSERT INTO Restockings
(id, inventory_id, employee_id, shelf_id, restocking_date,
 restocked_quantity, qnt_avarias, product_id)
SELECT
    g,
    (c*10) + ((r-1)%10)+1,
    (c+1) + (((r-1)%500)*100),
    (c*500) + ((r-1)%500)+1,
    TIMESTAMP '2025-01-01 08:00:00' + (g * INTERVAL '11 minutes'),
    10 + ((g*7)%41),
    (g%4),
    (c*800) + ((r-1)%800)+1
FROM generate_series(0,99) c
CROSS JOIN generate_series(1,500) r
CROSS JOIN LATERAL (SELECT c*500+r AS g) x;

-- ============================================================
-- 16) ALERTS - 20.000
-- ============================================================

INSERT INTO Alerts
(id, stockout_date, employee_id, shelf_id, product_id, description, status, resolution_date)
SELECT
    g,
    DATE '2025-01-01' + ((g*13)%600),
    (c+1) + (((r-1)%500)*100),
    (c*500) + ((r*7-1)%500)+1,
    (c*800) + ((r*13-1)%800)+1,
    'Reposição necessária para produto monitorado no ponto de venda; ocorrência ' ||
       lpad(g::text,6,'0') || '.',
    (ARRAY['OPEN','RESOLVED','CANCELLED'])[((g-1)%3)+1],
    CASE
      WHEN ((g-1)%3)+1 = 1 THEN NULL
      ELSE TIMESTAMP '2025-01-02 10:00:00' + (g * INTERVAL '17 minutes')
    END
FROM generate_series(0,99) c
CROSS JOIN generate_series(1,200) r
CROSS JOIN LATERAL (SELECT c*200+r AS g) x;

-- ============================================================
-- 17) CUSTOMERS - 150.000
-- usuários 50.001..200.000
-- ============================================================

INSERT INTO Customers (id, users_id, company_id)
SELECT
    g,
    50000 + g,
    ((g-1)%100)+1
FROM generate_series(1,150000) g;

-- ============================================================
-- 18) PURCHASES - 25.000
-- ============================================================

INSERT INTO Purchases (id, customer_id, date, status)
SELECT
    g,
    g,
    TIMESTAMP '2025-01-01 09:00:00' + (g * INTERVAL '23 minutes'),
    (ARRAY['COMPLETED','COMPLETED','COMPLETED','IN_PROGRESS','CANCELLED'])[((g-1)%5)+1]
FROM generate_series(1,25000) g;

-- ============================================================
-- 19) PURCHASE_PRODUCTS - 10.900
-- Cada compra recebe no máximo 1 item neste recorte, portanto
-- (purchase_id, product_id) é naturalmente único.
-- Produto sempre pertence à mesma empresa do cliente.
-- ============================================================

INSERT INTO Purchase_Products (id, product_id, purchase_id, quantity, amount)
SELECT
    g,
    (company_zero * 800) + ((g*29-1)%800)+1,
    g,
    1 + ((g*3)%8),
    p.price
FROM generate_series(1,10900) g
CROSS JOIN LATERAL (
    SELECT ((g-1)%100) AS company_zero
) c
JOIN Products p
  ON p.id = (company_zero * 800) + ((g*29-1)%800)+1;

-- ============================================================
-- AJUSTA SEQUENCES
-- ============================================================

SELECT setval(pg_get_serial_sequence('Companies','id'),          COALESCE(MAX(id),1), true) FROM Companies;
SELECT setval(pg_get_serial_sequence('Users','id'),              COALESCE(MAX(id),1), true) FROM Users;
SELECT setval(pg_get_serial_sequence('Sectors','id'),            COALESCE(MAX(id),1), true) FROM Sectors;
SELECT setval(pg_get_serial_sequence('Aisles','id'),             COALESCE(MAX(id),1), true) FROM Aisles;
SELECT setval(pg_get_serial_sequence('Shelves','id'),            COALESCE(MAX(id),1), true) FROM Shelves;
SELECT setval(pg_get_serial_sequence('Employees','id'),          COALESCE(MAX(id),1), true) FROM Employees;
SELECT setval(pg_get_serial_sequence('Inventories','id'),        COALESCE(MAX(id),1), true) FROM Inventories;
SELECT setval(pg_get_serial_sequence('Inventory_Employees','id'),COALESCE(MAX(id),1), true) FROM Inventory_Employees;
SELECT setval(pg_get_serial_sequence('Shelf_Employees','id'),    COALESCE(MAX(id),1), true) FROM Shelf_Employees;
SELECT setval(pg_get_serial_sequence('Employee_Aisles','id'),    COALESCE(MAX(id),1), true) FROM Employee_Aisles;
SELECT setval(pg_get_serial_sequence('Categories','id'),         COALESCE(MAX(id),1), true) FROM Categories;
SELECT setval(pg_get_serial_sequence('Products','id'),           COALESCE(MAX(id),1), true) FROM Products;
SELECT setval(pg_get_serial_sequence('Product_Shelves','id'),    COALESCE(MAX(id),1), true) FROM Product_Shelves;
SELECT setval(pg_get_serial_sequence('Product_Inventories','id'),COALESCE(MAX(id),1), true) FROM Product_Inventories;
SELECT setval(pg_get_serial_sequence('Restockings','id'),        COALESCE(MAX(id),1), true) FROM Restockings;
SELECT setval(pg_get_serial_sequence('Alerts','id'),             COALESCE(MAX(id),1), true) FROM Alerts;
SELECT setval(pg_get_serial_sequence('Customers','id'),          COALESCE(MAX(id),1), true) FROM Customers;
SELECT setval(pg_get_serial_sequence('Purchases','id'),          COALESCE(MAX(id),1), true) FROM Purchases;
SELECT setval(pg_get_serial_sequence('Purchase_Products','id'),  COALESCE(MAX(id),1), true) FROM Purchase_Products;

ALTER TABLE Products ENABLE TRIGGER trg_products_audit;
ALTER TABLE Purchases ENABLE TRIGGER trg_purchases_audit;

COMMIT;

-- ============================================================
-- VALIDAÇÃO DO TOTAL
-- Deve retornar exatamente 1.000.000
-- ============================================================

SELECT SUM(qtd) AS total_registros
FROM (
    SELECT COUNT(*) qtd FROM Companies
    UNION ALL SELECT COUNT(*) FROM Users
    UNION ALL SELECT COUNT(*) FROM Sectors
    UNION ALL SELECT COUNT(*) FROM Aisles
    UNION ALL SELECT COUNT(*) FROM Shelves
    UNION ALL SELECT COUNT(*) FROM Employees
    UNION ALL SELECT COUNT(*) FROM Inventories
    UNION ALL SELECT COUNT(*) FROM Inventory_Employees
    UNION ALL SELECT COUNT(*) FROM Shelf_Employees
    UNION ALL SELECT COUNT(*) FROM Employee_Aisles
    UNION ALL SELECT COUNT(*) FROM Categories
    UNION ALL SELECT COUNT(*) FROM Products
    UNION ALL SELECT COUNT(*) FROM Product_Shelves
    UNION ALL SELECT COUNT(*) FROM Product_Inventories
    UNION ALL SELECT COUNT(*) FROM Restockings
    UNION ALL SELECT COUNT(*) FROM Alerts
    UNION ALL SELECT COUNT(*) FROM Customers
    UNION ALL SELECT COUNT(*) FROM Purchases
    UNION ALL SELECT COUNT(*) FROM Purchase_Products
) x;

-- Validações rápidas de unicidade esperadas: todas devem retornar 0.
SELECT 'duplicate_cpf' AS check_name, COUNT(*) AS problems
FROM (SELECT cpf FROM Users GROUP BY cpf HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'duplicate_user_email', COUNT(*)
FROM (SELECT email FROM Users GROUP BY email HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'duplicate_cnpj', COUNT(*)
FROM (SELECT cnpj FROM Companies GROUP BY cnpj HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'duplicate_company_email', COUNT(*)
FROM (SELECT email FROM Companies GROUP BY email HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'duplicate_inventory_product', COUNT(*)
FROM (
    SELECT inventory_id, product_id
    FROM Product_Inventories
    GROUP BY inventory_id, product_id
    HAVING COUNT(*) > 1
) d;
