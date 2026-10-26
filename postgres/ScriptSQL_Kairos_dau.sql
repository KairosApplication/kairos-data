-- ==============================================================
-- KAIROS | 07 - DAILY ACTIVE USERS (DAU)
-- Metricas baseadas em eventos reais enviados PELO BACKEND.
-- Nao aumenta contagem por recarregar pagina varias vezes no dia.
-- Nao inclui 'Admins' (sao identidades internas separadas de Users).
-- Reexecutavel.
-- ==============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS User_Accesses (
    id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES Users (id),
    company_id INT NOT NULL REFERENCES Companies (id),
    access_date DATE NOT NULL,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, company_id, access_date)
);

CREATE INDEX IF NOT EXISTS idx_user_accesses_company_date
    ON User_Accesses (company_id, access_date);

CREATE OR REPLACE FUNCTION register_user_access(
    p_user_id INT,
    p_company_id INT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_access_date DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::DATE;
BEGIN
    -- O usuario deve pertencer a empresa como colaborador ou cliente.
    IF NOT EXISTS (
        SELECT 1 FROM Employees e
        WHERE e.users_id = p_user_id AND e.company_id = p_company_id
    ) AND NOT EXISTS (
        SELECT 1 FROM Customers c
        WHERE c.users_id = p_user_id AND c.company_id = p_company_id
    ) THEN
        RAISE EXCEPTION 'Usuario % nao pertence a empresa %.',
            p_user_id, p_company_id;
    END IF;

    INSERT INTO User_Accesses (user_id, company_id, access_date)
    VALUES (p_user_id, p_company_id, v_access_date)
    ON CONFLICT (user_id, company_id, access_date)
    DO UPDATE SET last_seen_at = CURRENT_TIMESTAMP;
END;
$$;

CREATE OR REPLACE VIEW vw_dau_daily AS
SELECT
    ua.company_id,
    ua.access_date,
    COUNT(*)::BIGINT AS daily_active_users
FROM User_Accesses ua
GROUP BY ua.company_id, ua.access_date;

-- Inclui dias sem atividade com DAU = 0 (ultimos 30 dias, por empresa).
CREATE OR REPLACE VIEW vw_dau_last_30_days AS
WITH dates AS (
    SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::DATE - day_offset
        AS access_date
    FROM generate_series(0, 29) AS days(day_offset)
)
SELECT
    c.id AS company_id,
    d.access_date,
    COALESCE(v.daily_active_users, 0)::BIGINT AS daily_active_users
FROM Companies c
CROSS JOIN dates d
LEFT JOIN vw_dau_daily v
    ON v.company_id = c.id AND v.access_date = d.access_date;

COMMIT;

-- INTEGRACAO OBRIGATORIA (implementar no backend depois do login
-- autenticado ou ao registrar uma sessao ativa no dia):
-- SELECT register_user_access(<ID_AUTENTICADO>, <EMPRESA_AUTORIZADA>);
-- NUNCA confiar em user_id ou company_id fornecidos pelo app.
-- Nao ha trigger de 'login' no PostgreSQL: sem esta chamada, DAU fica zero.

-- Teste manual com usuario existente e vinculado a empresa (substitua IDs):
-- SELECT register_user_access(1, 1);
-- SELECT * FROM vw_dau_daily WHERE company_id = 1 ORDER BY access_date DESC;
