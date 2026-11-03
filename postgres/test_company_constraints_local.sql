-- DIAGNOSTIC ONLY: shows which invalid cross-company writes the current DB accepts.
-- Only the fresh local dataload fixture is authorized. All inserted rows are rolled back.
BEGIN;
DO $$ BEGIN
    IF current_database()<>'kairos_modelagem_test' THEN
        RAISE EXCEPTION 'Requires dedicated local kairos_modelagem_test';
    END IF;
END $$;
CREATE TEMP TABLE company_test_results(name text,result text) ON COMMIT DROP;
DO $$
DECLARE scenario record;
BEGIN
    FOR scenario IN SELECT * FROM (VALUES
      ('product_category','INSERT INTO products(company_id,brand,price,name,category_id) VALUES(1,''DEMO'',1::money,''MODEL AUDIT'',21)'),
      ('inventory_sector','INSERT INTO inventories(company_id,sector_id) VALUES(1,11)'),
      ('product_inventory','INSERT INTO product_inventories(inventory_id,product_id,product_quantity) VALUES(11,1,1)'),
      ('employee_aisle','INSERT INTO employee_aisles(employee_id,aisle_id) VALUES(1,101)'),
      ('restocking_company','INSERT INTO restockings(inventory_id,employee_id,shelf_id,product_id,restocked_quantity) VALUES(1,101,1,801,1)'),
      ('purchase_product','INSERT INTO purchase_products(purchase_id,product_id,quantity,amount) VALUES(1,801,1,1::money)'),
      ('product_shelf','INSERT INTO product_shelves(product_id,shelf_id,product_quantity) VALUES(1,501,1)')
    ) AS tests(name,statement)
    LOOP
        BEGIN
            EXECUTE scenario.statement;
            INSERT INTO company_test_results VALUES(scenario.name,'ACCEPTED: missing database-level company constraint');
        EXCEPTION WHEN integrity_constraint_violation THEN
            INSERT INTO company_test_results VALUES(scenario.name,'REJECTED by database constraint');
        END;
    END LOOP;
END $$;
SELECT * FROM company_test_results ORDER BY name;
ROLLBACK;
