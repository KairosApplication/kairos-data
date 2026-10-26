-- ==============================================================
-- KAIROS | 08 - CTE RECURSIVA PARA HIERARQUIA DA LOJA
-- SETOR -> CORREDOR -> PRATELEIRA
-- Exemplo pratico de recursao na navegacao e nos relatorios.
-- Reexecutavel.
-- ==============================================================

CREATE OR REPLACE VIEW vw_store_hierarchy AS
WITH RECURSIVE nodes AS (
    SELECT
        ('sector:' || s.id)::TEXT AS node_id,
        NULL::TEXT AS parent_node_id,
        s.company_id,
        s.id AS sector_id,
        'SECTOR'::TEXT AS node_type,
        s.name::TEXT AS node_name
    FROM Sectors s

    UNION ALL

    SELECT
        ('aisle:' || a.id)::TEXT,
        ('sector:' || a.sector_id)::TEXT,
        s.company_id,
        s.id,
        'AISLE'::TEXT,
        ('Corredor ' || a.position)::TEXT
    FROM Aisles a
    JOIN Sectors s ON s.id = a.sector_id

    UNION ALL

    SELECT
        ('shelf:' || sh.id)::TEXT,
        ('aisle:' || sh.aisle_id)::TEXT,
        s.company_id,
        s.id,
        'SHELF'::TEXT,
        ('Prateleira ' || sh.id)::TEXT
    FROM Shelves sh
    JOIN Aisles a ON a.id = sh.aisle_id
    JOIN Sectors s ON s.id = a.sector_id
), tree AS (
    SELECT
        n.node_id, n.parent_node_id, n.company_id, n.sector_id,
        n.node_type, n.node_name, 0::INT AS depth,
        ARRAY[n.node_id]::TEXT[] AS visited,
        n.node_name::TEXT AS full_path
    FROM nodes n
    WHERE n.node_type = 'SECTOR'

    UNION ALL

    SELECT
        n.node_id, n.parent_node_id, n.company_id, n.sector_id,
        n.node_type, n.node_name, t.depth + 1,
        t.visited || n.node_id,
        t.full_path || ' > ' || n.node_name
    FROM tree t
    JOIN nodes n
      ON n.parent_node_id = t.node_id
     AND n.company_id = t.company_id
    WHERE t.depth < 8 AND NOT (n.node_id = ANY(t.visited))
)
SELECT
    company_id, sector_id, node_id, parent_node_id,
    node_type, node_name, depth, full_path
FROM tree;

-- Exemplo de consulta sem modificar dados.
SELECT company_id, sector_id, node_type, node_name, depth, full_path
FROM vw_store_hierarchy
WHERE company_id = 1
ORDER BY sector_id, full_path
LIMIT 40;

-- Observacao: a arvore atual tem 3 niveis fixos. A recursao facilita
-- a navegacao hierarquica, mas joins simples seriam suficientes hoje.
