-- ==============================================================
-- KAIROS | 06 - CATALOGO TECNICO DE DADOS
-- Documenta automaticamente tabelas e colunas do schema public.
-- Reexecutavel; novos campos aparecem apos reexecutar o script.
-- Nivel de acesso = classificacao documental, NAO GRANT/REVOKE.
-- ==============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS Data_Catalog (
    id BIGSERIAL PRIMARY KEY,
    schema_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    data_type TEXT NOT NULL,
    is_nullable BOOLEAN NOT NULL,
    is_primary_key BOOLEAN NOT NULL DEFAULT FALSE,
    is_foreign_key BOOLEAN NOT NULL DEFAULT FALSE,
    constraint_details TEXT,
    table_description TEXT NOT NULL,
    business_rule TEXT NOT NULL,
    access_level VARCHAR(20) NOT NULL
        CHECK (access_level IN ('INTERNAL', 'CONFIDENTIAL', 'RESTRICTED')),
    responsible_team TEXT NOT NULL DEFAULT 'Dados Kairos',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (schema_name, table_name, column_name)
);

INSERT INTO Data_Catalog (
    schema_name, table_name, column_name, data_type, is_nullable,
    is_primary_key, is_foreign_key, constraint_details,
    table_description, business_rule, access_level
)
SELECT
    c.table_schema,
    c.table_name,
    c.column_name,
    c.data_type || COALESCE(' (' || c.character_maximum_length::TEXT || ')', ''),
    c.is_nullable = 'YES',
    EXISTS (
        SELECT 1 FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = rel.relnamespace
        JOIN pg_attribute att ON att.attrelid = rel.oid
        WHERE ns.nspname = c.table_schema
          AND rel.relname = c.table_name
          AND att.attname = c.column_name
          AND con.contype = 'p'
          AND att.attnum = ANY(con.conkey)
    ) AS is_primary_key,
    EXISTS (
        SELECT 1 FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = rel.relnamespace
        JOIN pg_attribute att ON att.attrelid = rel.oid
        WHERE ns.nspname = c.table_schema
          AND rel.relname = c.table_name
          AND att.attname = c.column_name
          AND con.contype = 'f'
          AND att.attnum = ANY(con.conkey)
    ) AS is_foreign_key,
    (
        SELECT STRING_AGG(pg_get_constraintdef(con.oid), ' | ' ORDER BY con.conname)
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = rel.relnamespace
        JOIN pg_attribute att ON att.attrelid = rel.oid
        WHERE ns.nspname = c.table_schema
          AND rel.relname = c.table_name
          AND att.attname = c.column_name
          AND att.attnum = ANY(con.conkey)
    ) AS constraint_details,
    CASE LOWER(c.table_name)
        WHEN 'companies' THEN 'Supermercados e seus planos.'
        WHEN 'admins' THEN 'Administradores internos da plataforma Kairos.'
        WHEN 'users' THEN 'Identidades e credenciais dos usuarios.'
        WHEN 'employees' THEN 'Vinculo dos colaboradores com supermercados e cargo.'
        WHEN 'customers' THEN 'Vinculo dos clientes com supermercados.'
        WHEN 'sectors' THEN 'Setores das lojas e do estoque.'
        WHEN 'aisles' THEN 'Corredores organizados por setor.'
        WHEN 'shelves' THEN 'Prateleiras dos corredores.'
        WHEN 'inventories' THEN 'Estoques fisicos vinculados a empresas e setores.'
        WHEN 'inventory_employees' THEN 'Associacao entre estoque e colaboradores.'
        WHEN 'shelf_employees' THEN 'Associacao entre prateleiras e colaboradores.'
        WHEN 'employee_aisles' THEN 'Associacao entre colaboradores e corredores.'
        WHEN 'categories' THEN 'Categorias de produtos por empresa.'
        WHEN 'products' THEN 'Catalogo de produtos por empresa.'
        WHEN 'product_shelves' THEN 'Quantidades de produtos por prateleira.'
        WHEN 'product_inventories' THEN 'Quantidades de produtos por estoque.'
        WHEN 'restockings' THEN 'Historico permanente de reposicoes e avarias.'
        WHEN 'alerts' THEN 'Alertas de reposicao e seus estados.'
        WHEN 'purchases' THEN 'Compras realizadas por clientes.'
        WHEN 'purchase_products' THEN 'Itens, quantidades e valores das compras.'
        WHEN 'audits' THEN 'Registros de auditoria de operacoes SQL.'
        WHEN 'user_accesses' THEN 'Acessos diarios usados na metrica DAU.'
        WHEN 'data_catalog' THEN 'Metadados tecnicos e de governanca do proprio banco.'
        ELSE 'Tabela do schema public; descricao a revisar com o time.'
    END AS table_description,
    CASE
        WHEN LOWER(c.table_name) = 'employees' AND c.column_name = 'position'
            THEN 'Cargo permitido: MANAGER, STOCKER ou CASHIER.'
        WHEN LOWER(c.table_name) = 'restockings' AND c.column_name = 'qnt_avarias'
            THEN 'Quantidade de itens danificados, entre zero e a quantidade reposta.'
        WHEN LOWER(c.table_name) = 'restockings' AND c.column_name = 'restocked_quantity'
            THEN 'Quantidade total retirada do estoque para reposicao; deve ser positiva.'
        WHEN LOWER(c.table_name) = 'alerts' AND c.column_name = 'status'
            THEN 'Estado permitido: OPEN, RESOLVED ou CANCELLED.'
        WHEN LOWER(c.table_name) = 'purchases' AND c.column_name = 'status'
            THEN 'Estado permitido: IN_PROGRESS, COMPLETED ou CANCELLED.'
        WHEN LOWER(c.table_name) = 'products' AND c.column_name = 'price'
            THEN 'Preco do produto nao pode ser negativo.'
        WHEN LOWER(c.table_name) = 'user_accesses' AND c.column_name = 'access_date'
            THEN 'Dia de acesso no fuso America/Sao_Paulo; um registro por usuario, empresa e dia.'
        WHEN c.column_name = 'company_id'
            THEN 'Identificador da empresa; qualquer operacao deve respeitar o isolamento entre empresas.'
        WHEN c.column_name = 'id'
            THEN 'Identificador tecnico do registro.'
        WHEN c.column_name LIKE '%_id' OR c.column_name = 'users_id'
            THEN 'Referencia a entidade relacionada. Ver constraint_details para a FK.'
        ELSE 'Consultar os constraints da coluna e validar regras complementares com o responsavel.'
    END AS business_rule,
    CASE
        WHEN LOWER(c.table_name) IN ('users', 'admins') AND c.column_name IN
             ('password', 'senha', 'cpf', 'birth_date', 'email') THEN 'RESTRICTED'
        WHEN LOWER(c.table_name) IN ('audits', 'data_catalog') THEN 'CONFIDENTIAL'
        WHEN LOWER(c.table_name) = 'users' THEN 'CONFIDENTIAL'
        WHEN LOWER(c.table_name) = 'customers' THEN 'CONFIDENTIAL'
        WHEN LOWER(c.table_name) = 'user_accesses' THEN 'CONFIDENTIAL'
        ELSE 'INTERNAL'
    END AS access_level
FROM information_schema.columns c
JOIN information_schema.tables t
  ON t.table_schema = c.table_schema
 AND t.table_name = c.table_name
WHERE c.table_schema = 'public'
  AND t.table_type = 'BASE TABLE'
ON CONFLICT (schema_name, table_name, column_name)
DO UPDATE SET
    data_type = EXCLUDED.data_type,
    is_nullable = EXCLUDED.is_nullable,
    is_primary_key = EXCLUDED.is_primary_key,
    is_foreign_key = EXCLUDED.is_foreign_key,
    constraint_details = EXCLUDED.constraint_details,
    table_description = EXCLUDED.table_description,
    business_rule = EXCLUDED.business_rule,
    access_level = EXCLUDED.access_level,
    updated_at = CURRENT_TIMESTAMP;

-- Se alguma coluna for removida do schema, retira entrada desatualizada.
DELETE FROM Data_Catalog dc
WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = dc.schema_name
      AND c.table_name = dc.table_name
      AND c.column_name = dc.column_name
);

COMMIT;

-- Conferencias (somente leitura).
SELECT table_name, COUNT(*) AS documented_columns
FROM Data_Catalog
GROUP BY table_name
ORDER BY table_name;

SELECT table_name, column_name, access_level, business_rule
FROM Data_Catalog
WHERE access_level <> 'INTERNAL'
ORDER BY table_name, column_name;

-- IMPORTANTE: classificacao nao cria permissao de acesso. O backend
-- continua responsavel pela autorizacao; avaliar GRANT/REVOKE depois.
