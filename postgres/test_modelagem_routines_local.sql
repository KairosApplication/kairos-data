-- Reversible smoke test, only on a NEW local dataload fixture. Never on Aiven.
BEGIN;
DO $$
DECLARE product_test int;
        purchase_test int;
        restockings_before bigint;
        stock_before int;
BEGIN
    IF current_database()<>'kairos_modelagem_test' THEN
        RAISE EXCEPTION 'Requires dedicated local modelagem database';
    END IF;
    INSERT INTO Products(company_id,brand,price,name,category_id)
    VALUES(1,'DEMO-OLD',1::money,'MODELAGEM AUDIT DEMO',1) RETURNING id INTO product_test;
    UPDATE Products SET brand='DEMO-NEW' WHERE id=product_test;
    DELETE FROM Products WHERE id=product_test;
    IF (SELECT count(*) FROM Audits WHERE table_name='products' AND record_id=product_test)<>3
       OR NOT EXISTS (SELECT 1 FROM Audits WHERE table_name='products' AND record_id=product_test
            AND operation='UPDATE' AND old_data->>'brand'='DEMO-OLD'
            AND new_data->>'brand'='DEMO-NEW' AND users=CURRENT_USER)
       OR NOT EXISTS (SELECT 1 FROM Audits WHERE table_name='products' AND record_id=product_test
            AND operation='INSERT' AND old_data IS NULL AND new_data IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM Audits WHERE table_name='products' AND record_id=product_test
            AND operation='DELETE' AND old_data IS NOT NULL AND new_data IS NULL) THEN
        RAISE EXCEPTION 'Audit NEW/OLD/TG_OP/CURRENT_USER check failed';
    END IF;
    IF NOT check_product_availability(1,1,1) THEN
        RAISE EXCEPTION 'Availability function failed for dataload fixture';
    END IF;
    SELECT count(*) INTO restockings_before FROM Restockings;
    SELECT product_quantity INTO stock_before FROM Product_Inventories WHERE inventory_id=1 AND product_id=1;
    CALL perform_restocking(1,101,1,1,1,0);
    IF (SELECT count(*) FROM Restockings)<>restockings_before+1
       OR (SELECT product_quantity FROM Product_Inventories WHERE inventory_id=1 AND product_id=1)<>stock_before-1 THEN
        RAISE EXCEPTION 'Restocking procedure did not record movement';
    END IF;
    INSERT INTO Purchases(customer_id,status) VALUES(1,'IN_PROGRESS') RETURNING id INTO purchase_test;
    INSERT INTO Purchase_Products(product_id,purchase_id,quantity,amount)
    SELECT 1,purchase_test,1,price FROM Products WHERE id=1;
    CALL complete_purchase(purchase_test);
    IF (SELECT status FROM Purchases WHERE id=purchase_test)<>'COMPLETED'
       OR calculate_purchase_total(purchase_test)<>(SELECT price FROM Products WHERE id=1) THEN
        RAISE EXCEPTION 'Purchase procedure/total function failed';
    END IF;
    RAISE NOTICE 'PASS: audit snapshots/author, availability, restocking and purchase procedures/total';
END $$;
ROLLBACK;
