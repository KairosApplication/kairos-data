-- Somente copia descartavel preparada. Simulacao reversivel A/B/C/D.
BEGIN;
SET LOCAL TIME ZONE 'America/Sao_Paulo';
DO $$
DECLARE
    customer int;
    company int;
    product int;
    product2 int;
    purchase int;
    before_count bigint;
    before_revenue numeric;
    other_before jsonb;
    other_after jsonb;
BEGIN
    IF current_database() NOT IN ('kairos_demo', 'kairos_restore')
       OR current_setting('kairos.demo_authorized_database', true) IS DISTINCT FROM current_database() THEN
        RAISE EXCEPTION 'Teste exige banco demo explicitamente autorizado';
    END IF;
    SELECT c.id, c.company_id, pi.product_id INTO STRICT customer, company, product
    FROM Customers c JOIN Products p ON p.company_id = c.company_id
    JOIN Product_Inventories pi ON pi.product_id = p.id
    WHERE pi.product_quantity >= 2 ORDER BY c.id, p.id LIMIT 1;
    SELECT coalesce(sum(purchases_count),0), coalesce(sum(revenue),0)
    INTO before_count, before_revenue FROM vw_bi_sales_14d WHERE company_id = company;
    IF before_count = 0 THEN RAISE EXCEPTION 'Cenario A sem historico'; END IF;
    SELECT jsonb_agg(to_jsonb(v) ORDER BY company_id, date_key) INTO other_before
    FROM vw_bi_sales_14d v WHERE company_id <> company;
    INSERT INTO Purchases(customer_id, date, status)
    VALUES (customer, localtimestamp, 'IN_PROGRESS') RETURNING id INTO purchase;
    SELECT p.id INTO STRICT product2 FROM Products p
    JOIN Product_Inventories pi ON pi.product_id = p.id
    WHERE p.company_id = company AND p.id <> product AND pi.product_quantity >= 1
    ORDER BY p.id LIMIT 1;
    -- Dois itens na mesma compra: verifica que COUNT nao duplica.
    INSERT INTO Purchase_Products(product_id, purchase_id, quantity, amount)
    VALUES (product, purchase, 2, 7.50::money), (product2, purchase, 1, 5::money);
    IF (SELECT sum(purchases_count) FROM vw_bi_sales_14d WHERE company_id = company) <> before_count THEN
        RAISE EXCEPTION 'Compra IN_PROGRESS entrou em vendas';
    END IF;
    CALL complete_purchase(purchase);
    IF (SELECT sum(purchases_count) FROM vw_bi_sales_14d WHERE company_id = company) <> before_count + 1
       OR (SELECT sum(revenue) FROM vw_bi_sales_14d WHERE company_id = company) <> before_revenue + 20 THEN
        RAISE EXCEPTION 'Cenario C: delta ou historico incorreto';
    END IF;
    SELECT jsonb_agg(to_jsonb(v) ORDER BY company_id, date_key) INTO other_after
    FROM vw_bi_sales_14d v WHERE company_id <> company;
    IF other_before IS DISTINCT FROM other_after THEN RAISE EXCEPTION 'Cenario D: outra empresa mudou'; END IF;
    UPDATE Purchases SET status = 'CANCELLED' WHERE id = purchase;
    IF (SELECT sum(purchases_count) FROM vw_bi_sales_14d WHERE company_id = company) <> before_count
       OR (SELECT sum(revenue) FROM vw_bi_sales_14d WHERE company_id = company) <> before_revenue THEN
        RAISE EXCEPTION 'Compra CANCELLED entrou em vendas';
    END IF;
    RAISE NOTICE 'PASS A/B/C/D: historico preservado, +1 compra, +20 receita, outras empresas identicas';
END $$;
ROLLBACK;
-- Sequences podem avancar mesmo com rollback; nunca executar em producao.
