-- ============================================================
-- FUNCTIONS
-- ============================================================

-- RECOMMEND PRODUCTS

CREATE OR REPLACE FUNCTION recommend_products(
    p_customer_id INT,
    p_limit INT
)
RETURNS TABLE (
    product_id INT,
    product_name VARCHAR(100),
    category_id INT,
    category_name VARCHAR(50)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id AS product_id,
        p.name AS product_name,
        c.id AS category_id,
        c.category AS category_name
    FROM Products p
    JOIN Categories c
        ON c.id = p.category_id
       AND c.company_id = p.company_id
    JOIN Customers cu
        ON cu.id = p_customer_id
       AND cu.company_id = p.company_id
    JOIN (
        SELECT
            p2.category_id,
            SUM(pp.quantity) AS purchased_quantity
        FROM Purchases pu
        JOIN Purchase_Products pp
            ON pp.purchase_id = pu.id
        JOIN Products p2
            ON p2.id = pp.product_id
        WHERE pu.customer_id = p_customer_id
          AND pu.status = 'COMPLETED'
          AND p2.company_id = (
              SELECT company_id
              FROM Customers
              WHERE id = p_customer_id
          )
        GROUP BY p2.category_id
    ) categories
        ON categories.category_id = p.category_id
    WHERE p.company_id = (
        SELECT company_id
        FROM Customers
        WHERE id = p_customer_id
    )
    AND NOT EXISTS (
        SELECT 1
        FROM Purchases pu2
        JOIN Purchase_Products pp2
            ON pp2.purchase_id = pu2.id
        WHERE pu2.customer_id = p_customer_id
          AND pp2.product_id = p.id
          AND pu2.status = 'COMPLETED'
    )
    ORDER BY
        categories.purchased_quantity DESC,
        p.name
    LIMIT p_limit;
END;
$$;


-- CALCULATE PURCHASE TOTAL

CREATE OR REPLACE FUNCTION calculate_purchase_total(
    p_purchase_id INT
)
RETURNS MONEY
LANGUAGE plpgsql
AS $$
DECLARE
    v_total NUMERIC(12,2);
BEGIN
    SELECT COALESCE(
        SUM(pp.amount::NUMERIC * pp.quantity),
        0
    )
    INTO v_total
    FROM Purchase_Products pp
    WHERE pp.purchase_id = p_purchase_id;

    RETURN v_total::MONEY;
END;
$$;


-- CHECK PRODUCT AVAILABILITY

CREATE OR REPLACE FUNCTION check_product_availability(
    p_product_id INT,
    p_inventory_id INT,
    p_quantity INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_quantity INT;
    v_product_company_id INT;
    v_inventory_company_id INT;
BEGIN
    IF p_quantity <= 0 THEN
        RETURN FALSE;
    END IF;

    SELECT company_id
    INTO v_product_company_id
    FROM Products
    WHERE id = p_product_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    SELECT company_id
    INTO v_inventory_company_id
    FROM Inventories
    WHERE id = p_inventory_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF v_product_company_id <> v_inventory_company_id THEN
        RETURN FALSE;
    END IF;

    SELECT product_quantity
    INTO v_quantity
    FROM Product_Inventories
    WHERE product_id = p_product_id
      AND inventory_id = p_inventory_id;

    RETURN COALESCE(v_quantity, 0) >= p_quantity;
END;
$$;


-- ============================================================
-- PROCEDURES
-- ============================================================

-- COMPLETE PURCHASE

CREATE OR REPLACE PROCEDURE complete_purchase(
    p_purchase_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_customer_id INT;
    v_company_id INT;
    v_item RECORD;
    v_inventory RECORD;
    v_remaining_quantity INT;
    v_quantity_to_remove INT;
BEGIN
    SELECT
        pu.status,
        pu.customer_id,
        c.company_id
    INTO
        v_status,
        v_customer_id,
        v_company_id
    FROM Purchases pu
    JOIN Customers c
        ON c.id = pu.customer_id
    WHERE pu.id = p_purchase_id
    FOR UPDATE OF pu;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Purchase % not found.',
            p_purchase_id;
    END IF;

    IF v_status <> 'IN_PROGRESS' THEN
        RAISE EXCEPTION
            'Purchase % is not in progress.',
            p_purchase_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM Purchase_Products
        WHERE purchase_id = p_purchase_id
    ) THEN
        RAISE EXCEPTION
            'Purchase % cannot be completed without products.',
            p_purchase_id;
    END IF;

    FOR v_item IN
        SELECT
            pp.product_id,
            pp.quantity
        FROM Purchase_Products pp
        JOIN Products p
            ON p.id = pp.product_id
        WHERE pp.purchase_id = p_purchase_id
          AND p.company_id = v_company_id
    LOOP

        v_remaining_quantity := v_item.quantity;

        FOR v_inventory IN
            SELECT
                pi.inventory_id,
                pi.product_quantity
            FROM Product_Inventories pi
            JOIN Inventories i
                ON i.id = pi.inventory_id
            WHERE pi.product_id = v_item.product_id
              AND i.company_id = v_company_id
              AND pi.product_quantity > 0
            ORDER BY pi.inventory_id
            FOR UPDATE OF pi
        LOOP

            EXIT WHEN v_remaining_quantity <= 0;

            v_quantity_to_remove := LEAST(
                v_remaining_quantity,
                v_inventory.product_quantity
            );

            UPDATE Product_Inventories
            SET product_quantity =
                product_quantity - v_quantity_to_remove
            WHERE product_id = v_item.product_id
              AND inventory_id = v_inventory.inventory_id;

            v_remaining_quantity :=
                v_remaining_quantity - v_quantity_to_remove;

        END LOOP;

        IF v_remaining_quantity > 0 THEN
            RAISE EXCEPTION
                'Product % does not have enough inventory for company %.',
                v_item.product_id,
                v_company_id;
        END IF;

    END LOOP;

    UPDATE Purchases
    SET status = 'COMPLETED',
        date = COALESCE(date, CURRENT_TIMESTAMP)
    WHERE id = p_purchase_id;

END;
$$;


-- PERFORM RESTOCKING

CREATE OR REPLACE PROCEDURE perform_restocking(
    p_inventory_id INT,
    p_employee_id INT,
    p_shelf_id INT,
    p_product_id INT,
    p_quantity INT,
    p_qnt_avarias INT DEFAULT 0
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacity INT;
    v_current_quantity INT;
    v_inventory_company_id INT;
    v_employee_company_id INT;
    v_product_company_id INT;
    v_shelf_sector_company_id INT;
    v_aisle_id INT;
    v_sector_id INT;
BEGIN
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION
            'The restocking quantity must be greater than zero.';
    END IF;

    IF p_qnt_avarias < 0 THEN
        RAISE EXCEPTION
            'The number of damaged products cannot be negative.';
    END IF;

    IF p_qnt_avarias > p_quantity THEN
        RAISE EXCEPTION
            'The number of damaged products cannot exceed the restocking quantity.';
    END IF;

    SELECT company_id
    INTO v_inventory_company_id
    FROM Inventories
    WHERE id = p_inventory_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Inventory % not found.',
            p_inventory_id;
    END IF;

    SELECT company_id
    INTO v_employee_company_id
    FROM Employees
    WHERE id = p_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Employee % not found.',
            p_employee_id;
    END IF;

    SELECT company_id
    INTO v_product_company_id
    FROM Products
    WHERE id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Product % not found.',
            p_product_id;
    END IF;

    SELECT
        s.maximum_capacity,
        a.id,
        a.sector_id
    INTO
        v_capacity,
        v_aisle_id,
        v_sector_id
    FROM Shelves s
    JOIN Aisles a
        ON a.id = s.aisle_id
    WHERE s.id = p_shelf_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Shelf % not found.',
            p_shelf_id;
    END IF;

    SELECT company_id
    INTO v_shelf_sector_company_id
    FROM Sectors
    WHERE id = v_sector_id;

    IF v_inventory_company_id <> v_employee_company_id THEN
        RAISE EXCEPTION
            'Inventory and employee belong to different companies.';
    END IF;

    IF v_inventory_company_id <> v_product_company_id THEN
        RAISE EXCEPTION
            'Inventory and product belong to different companies.';
    END IF;

    IF v_inventory_company_id <> v_shelf_sector_company_id THEN
        RAISE EXCEPTION
            'Inventory and shelf belong to different companies.';
    END IF;

    SELECT COALESCE(
        SUM(product_quantity),
        0
    )
    INTO v_current_quantity
    FROM Product_Shelves
    WHERE shelf_id = p_shelf_id;

    IF v_current_quantity + (p_quantity - p_qnt_avarias)
       > v_capacity THEN
        RAISE EXCEPTION
            'The restocking exceeds the shelf maximum capacity.';
    END IF;

    UPDATE Product_Inventories
    SET product_quantity =
        product_quantity - p_quantity
    WHERE inventory_id = p_inventory_id
      AND product_id = p_product_id
      AND product_quantity >= p_quantity;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Insufficient inventory to perform restocking.';
    END IF;

    IF p_quantity - p_qnt_avarias > 0 THEN
        INSERT INTO Product_Shelves (
            product_id,
            shelf_id,
            product_quantity
        )
        VALUES (
            p_product_id,
            p_shelf_id,
            p_quantity - p_qnt_avarias
        )
        ON CONFLICT (product_id, shelf_id)
        DO UPDATE SET
            product_quantity =
                Product_Shelves.product_quantity
                + EXCLUDED.product_quantity;
    END IF;

    INSERT INTO Restockings (
        inventory_id,
        employee_id,
        shelf_id,
        restocking_date,
        restocked_quantity,
        qnt_avarias,
        product_id
    )
    VALUES (
        p_inventory_id,
        p_employee_id,
        p_shelf_id,
        CURRENT_TIMESTAMP,
        p_quantity,
        p_qnt_avarias,
        p_product_id
    );

END;
$$;


-- ============================================================
-- TRIGGERS
-- ============================================================

-- AUDIT TRIGGER FUNCTION

CREATE OR REPLACE FUNCTION register_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN
        INSERT INTO Audits (
            table_name,
            operation,
            old_data,
            new_data,
            record_id,
            users
        )
        VALUES (
            TG_TABLE_NAME,
            TG_OP,
            NULL,
            TO_JSONB(NEW),
            NEW.id,
            CURRENT_USER
        );

        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO Audits (
            table_name,
            operation,
            old_data,
            new_data,
            record_id,
            users
        )
        VALUES (
            TG_TABLE_NAME,
            TG_OP,
            TO_JSONB(OLD),
            TO_JSONB(NEW),
            NEW.id,
            CURRENT_USER
        );

        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO Audits (
            table_name,
            operation,
            old_data,
            new_data,
            record_id,
            users
        )
        VALUES (
            TG_TABLE_NAME,
            TG_OP,
            TO_JSONB(OLD),
            NULL,
            OLD.id,
            CURRENT_USER
        );

        RETURN OLD;
    END IF;

    RETURN NULL;

END;
$$;


-- PRODUCTS AUDIT

CREATE TRIGGER trg_products_audit
AFTER INSERT OR UPDATE OR DELETE
ON Products
FOR EACH ROW
EXECUTE FUNCTION register_audit();


-- PURCHASES AUDIT

CREATE TRIGGER trg_purchases_audit
AFTER INSERT OR UPDATE OR DELETE
ON Purchases
FOR EACH ROW
EXECUTE FUNCTION register_audit();