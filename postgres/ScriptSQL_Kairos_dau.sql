-- DAU: called by authenticated backend activity. Re-executable; no business data removal.
BEGIN;
-- Additive and compatible with the kairos-data DAU script already installed.
CREATE TABLE IF NOT EXISTS public.User_Accesses (
    id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES public.Users(id),
    company_id INT NOT NULL REFERENCES public.Companies(id),
    access_date DATE NOT NULL,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, company_id, access_date)
);

-- Refuse incompatible objects without dropping, rewriting or silently deduplicating data.
DO $$
BEGIN
    IF EXISTS (
        SELECT * FROM (VALUES ('id','bigint'),('user_id','integer'),('company_id','integer'),
            ('access_date','date'),('first_seen_at','timestamp with time zone'),
            ('last_seen_at','timestamp with time zone')) expected(name,type)
        EXCEPT
        SELECT column_name::text,data_type::text FROM information_schema.columns
        WHERE table_schema='public' AND table_name='user_accesses' AND is_nullable='NO'
    ) THEN
        RAISE EXCEPTION 'Incompatible public.user_accesses: review existing columns before migration';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.user_accesses'::regclass
        AND contype='u' AND pg_get_constraintdef(oid)='UNIQUE (user_id, company_id, access_date)') THEN
        ALTER TABLE public.user_accesses ADD CONSTRAINT uq_user_accesses_identity
            UNIQUE(user_id,company_id,access_date);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_user_accesses_company_date ON public.User_Accesses(company_id,access_date);

CREATE OR REPLACE FUNCTION public.register_user_access(p_user_id INT,p_company_id INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_seen_at timestamptz := clock_timestamp();
    v_access_date date := (v_seen_at AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.Employees WHERE users_id=p_user_id AND company_id=p_company_id)
       AND NOT EXISTS (SELECT 1 FROM public.Customers WHERE users_id=p_user_id AND company_id=p_company_id) THEN
        RAISE EXCEPTION 'User has no authorized company membership' USING ERRCODE='42501';
    END IF;
    INSERT INTO public.User_Accesses(user_id,company_id,access_date,first_seen_at,last_seen_at)
    VALUES(p_user_id,p_company_id,v_access_date,v_seen_at,v_seen_at)
    ON CONFLICT(user_id,company_id,access_date)
    DO UPDATE SET last_seen_at=GREATEST(public.User_Accesses.last_seen_at,EXCLUDED.last_seen_at);
END $$;

CREATE OR REPLACE VIEW public.vw_dau_daily AS
SELECT company_id,access_date,count(*)::bigint AS daily_active_users
FROM public.User_Accesses GROUP BY company_id,access_date;

CREATE OR REPLACE VIEW public.vw_dau_last_30_days AS
WITH dates AS (
    SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date-day_offset AS access_date
    FROM generate_series(0,29) AS days(day_offset)
)
SELECT c.id AS company_id,d.access_date,COALESCE(v.daily_active_users,0)::bigint AS daily_active_users
FROM public.Companies c CROSS JOIN dates d
LEFT JOIN public.vw_dau_daily v ON v.company_id=c.id AND v.access_date=d.access_date;

COMMIT;
