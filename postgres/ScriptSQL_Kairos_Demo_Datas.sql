-- Somente copia descartavel. Configure na MESMA sessao antes de executar:
-- SET kairos.demo_authorized_database = 'kairos_demo';
-- SET kairos.demo_reference_date = '2026-11-02'; -- opcional; default hoje SP
BEGIN;
SET LOCAL TIME ZONE 'America/Sao_Paulo';
SET LOCAL search_path = public, pg_catalog;
DO $$
BEGIN
    IF current_database() NOT IN ('kairos_demo', 'kairos_restore')
       OR current_setting('kairos.demo_authorized_database', true)
          IS DISTINCT FROM current_database() THEN
        RAISE EXCEPTION 'Exige kairos_demo/kairos_restore e autorizacao explicita da sessao';
    END IF;
END $$;

-- Serializa preparacoes; bloqueia escritas concorrentes ate o commit.
-- Bloco PostgreSQL nativo: o parser SQL generico do CI nao suporta LOCK TABLE.
DO $$
BEGIN
    LOCK TABLE Purchases, Restockings, Alerts IN SHARE ROW EXCLUSIVE MODE;
END $$;
CREATE TABLE IF NOT EXISTS kairos_demo_date_runs (
    reference_date date PRIMARY KEY,
    prepared_at timestamptz NOT NULL DEFAULT current_timestamp,
    before_counts jsonb NOT NULL,
    after_counts jsonb NOT NULL
);
DO $$
DECLARE
    ref date := COALESCE(NULLIF(current_setting('kairos.demo_reference_date', true), '')::date,
                         (current_timestamp AT TIME ZONE 'America/Sao_Paulo')::date);
    before_n jsonb;
    after_n jsonb;
BEGIN
    IF EXISTS (SELECT 1 FROM kairos_demo_date_runs WHERE reference_date = ref) THEN
        RAISE NOTICE 'Data % ja preparada; nenhuma linha alterada', ref;
        RETURN;
    END IF;
    -- Uma copia nao deve ser repreparada depois de receber operacoes da feira.
    IF EXISTS (SELECT 1 FROM kairos_demo_date_runs) THEN
        RAISE EXCEPTION 'Copia preparada para outra data; restaure uma nova copia descartavel';
    END IF;
    SELECT jsonb_build_object('purchases', (SELECT count(*) FROM Purchases),
        'restockings', (SELECT count(*) FROM Restockings),
        'alerts', (SELECT count(*) FROM Alerts),
        'purchase_products', (SELECT count(*) FROM Purchase_Products)) INTO before_n;

    -- ID e aritmetica bigint: deterministico, sem overflow de integer.
    -- Dias ref-13..ref-1, horarios 08:00..21:59:59 (SP, timestamp sem fuso).
    UPDATE Purchases SET date = (ref - 13 + ((id::bigint - 1) % 13)::int)
        + time '08:00' + ((id::bigint * 7919) % 50400) * interval '1 second';
    UPDATE Restockings SET restocking_date = (ref - 13 + ((id::bigint - 1) % 13)::int)
        + time '08:00' + ((id::bigint * 7907) % 50400) * interval '1 second';
    UPDATE Alerts SET
        stockout_date = ref - 13 + ((id::bigint - 1) % 13)::int,
        resolution_date = CASE WHEN status = 'RESOLVED' OR resolution_date IS NOT NULL
            THEN (ref - 13 + ((id::bigint - 1) % 13)::int) + time '09:00'
                 + ((id::bigint * 7879) % 43200) * interval '1 second'
            ELSE NULL END;

    SELECT jsonb_build_object('purchases', (SELECT count(*) FROM Purchases),
        'restockings', (SELECT count(*) FROM Restockings),
        'alerts', (SELECT count(*) FROM Alerts),
        'purchase_products', (SELECT count(*) FROM Purchase_Products)) INTO after_n;
    IF before_n <> after_n THEN
        RAISE EXCEPTION 'Contagens alteradas: % -> %', before_n, after_n;
    END IF;
    IF EXISTS (SELECT 1 FROM Alerts WHERE resolution_date < stockout_date::timestamp
        OR (status = 'RESOLVED' AND resolution_date IS NULL)) THEN
        RAISE EXCEPTION 'Cronologia dos alertas invalida';
    END IF;
    INSERT INTO kairos_demo_date_runs(reference_date, before_counts, after_counts)
    VALUES (ref, before_n, after_n);
END $$;
COMMIT;
