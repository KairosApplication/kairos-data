-- KAIROS | Reparacao das atribuicoes do DATALOAD DE DESENVOLVIMENTO.
-- Execute NO POSTGRESQL, uma unica vez apos o dataload antigo.
-- Variante tolerante a Employee extra fora do intervalo id=1..50000.
-- NAO execute em producao ou em dados reais: as atribuicoes serao redistribuidas.
-- Nao apaga linhas nem altera IDs de Employees/Aisles/Shelves.
-- As verificacoes abaixo abortam se nao identificarem o conjunto ficticio esperado.
-- Permite empregados adicionais (id > 50000), preservando-os e suas atribuicoes.

BEGIN;

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM Companies) <> 100
       OR (SELECT COUNT(*) FROM Employees WHERE id BETWEEN 1 AND 50000) <> 50000
       OR (SELECT COUNT(*) FROM Aisles) <> 10000
       OR (SELECT COUNT(*) FROM Shelves) <> 50000
       OR (SELECT COUNT(*) FROM Employee_Aisles WHERE employee_id BETWEEN 1 AND 50000) <> 50000
       OR (SELECT COUNT(*) FROM Shelf_Employees WHERE employee_id BETWEEN 1 AND 50000) <> 50000 THEN
        RAISE EXCEPTION 'Ambiente nao corresponde ao dataload Kairos de 1M; nenhuma atribuicao foi alterada';
    END IF;

    IF EXISTS (
        SELECT 1 FROM Employees e
        WHERE e.id BETWEEN 1 AND 50000
          AND e.company_id <> ((e.id - 1) % 100) + 1
    ) OR EXISTS (
        SELECT 1 FROM Aisles a
        JOIN Sectors s ON s.id = a.sector_id
        WHERE s.company_id <> ((a.id - 1) / 100) + 1
    ) OR EXISTS (
        SELECT 1 FROM Shelves sh
        JOIN Aisles a ON a.id = sh.aisle_id
        JOIN Sectors s ON s.id = a.sector_id
        WHERE s.company_id <> ((sh.id - 1) / 500) + 1
    ) THEN
        RAISE EXCEPTION 'IDs/empresas diferentes do dataload conhecido; reparacao cancelada';
    END IF;

    IF EXISTS (
        SELECT 1 FROM Employee_Aisles
        WHERE employee_id BETWEEN 1 AND 50000
        GROUP BY employee_id HAVING COUNT(*) <> 1
    ) OR EXISTS (
        SELECT 1 FROM Shelf_Employees
        WHERE employee_id BETWEEN 1 AND 50000
        GROUP BY employee_id HAVING COUNT(*) <> 1
    ) THEN
        RAISE EXCEPTION 'Ha funcionarios com varias atribuicoes; reparacao automatica cancelada';
    END IF;
END;
$$;

-- Cada empresa tem 100 corredores; distribui os 500 funcionarios da empresa
-- entre esses corredores. Cada corredor recebe 5 funcionarios, sendo 4 STOCKER.
UPDATE Employee_Aisles ea
SET aisle_id =
    (e.company_id - 1) * 100
    + (((((e.id - 1) / 100) % 100) + (((e.id - 1) / 100) / 100)) % 100)
    + 1
FROM Employees e
WHERE e.id = ea.employee_id
  AND e.id BETWEEN 1 AND 50000
  AND ea.aisle_id IS DISTINCT FROM (
      (e.company_id - 1) * 100
      + (((((e.id - 1) / 100) % 100) + (((e.id - 1) / 100) / 100)) % 100)
      + 1
  );

-- Cada empresa tem 500 prateleiras; associa uma prateleira da propria empresa
-- a cada um dos 500 funcionarios (a consulta do grafo filtra os STOCKER).
UPDATE Shelf_Employees se
SET shelf_id = (e.company_id - 1) * 500 + ((e.id - 1) / 100) + 1
FROM Employees e
WHERE e.id = se.employee_id
  AND e.id BETWEEN 1 AND 50000
  AND se.shelf_id IS DISTINCT FROM (
      (e.company_id - 1) * 500 + ((e.id - 1) / 100) + 1
  );

COMMIT;

-- Verifique depois executando 04_postgres_diagnostics.sql.
-- O resultado esperado nas quatro verificacoes e 0.
