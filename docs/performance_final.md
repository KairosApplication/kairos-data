# Performance final — PostgreSQL, 02/11/2026

## Ambiente e método

PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2), Docker local, banco novo `kairos_modelagem_test`, container `kairos-modelagem-fixed` com `--network none`, sem porta publicada. Nenhum acesso Aiven ou banco compartilhado. Carga comercial efetiva: **1.050.000 registros** (o nome histórico do arquivo contém 1M). 50.000 reposições, 20.000 alertas, 100.000 relações produto/estoque e 25.000 compras.

Usados schema/rotinas/dataload originais, com a correção documentada das resoluções de alertas. ANALYZE antes da medição. Cada cenário teve duas execuções de aquecimento e sete medidas de EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON); a tabela usa a mediana das sete. Não foram desabilitados scans nem alterados custos do planejador. Bench foi executado após a compilação anterior terminar; outros serviços do host continuaram ativos.

Os quatro índices opcionais foram retirados/criados somente dentro de transação no banco descartável e o DDL foi revertido. PKs/UNIQUE não foram removidos. A lista completa de índices antes e depois do ROLLBACK foi comparada e ficou idêntica. Resultados das consultas foram comparados, não somente tempos.

## Números observados

| Consulta | Linhas | Antes ms | Depois ms | Hits antes/depois | Reads antes/depois | Estratégia antes → depois |
|---|---:|---:|---:|---|---|---|
| restockings | 2 | 2.147 | 0.012 | 417 / 4 | 0 / 0 | Seq Scan + Sort → Index Scan |
| open_alerts | 1 | 1.260 | 0.014 | 371 / 3 | 0 / 0 | Seq Scan + Sort → Index Scan |
| product_inventory | 10 | 4.168 | 0.011 | 541 / 3 | 0 / 0 | Seq Scan → Index Scan |
| customer_purchases | 1 | 0.945 | 0.009 | 184 / 3 | 0 / 0 | Seq Scan + Sort → Index Scan |

Tempos são do Execution Time, não do tempo de rede/criação do índice. Buffers são os do nó raiz de um plano representativo; não somar novamente buffers de filhos. Todos os reads foram zero: este ensaio mede cache aquecido, não disco frio. Nenhum Bitmap Scan foi escolhido nestes quatro planos; não é falha do teste.

## Consultas e planos

### restockings

```sql
SELECT id,employee_id,product_id,restocking_date FROM restockings WHERE employee_id=101 ORDER BY restocking_date DESC LIMIT 25;
```

before:

```text
Limit; rows=2; shared hits=417; reads=0
  Sort; rows=2; shared hits=417; reads=0
    Seq Scan; rows=2; shared hits=417; reads=0
```

after:

```text
Limit; rows=2; shared hits=4; reads=0
  Index Scan using idx_restockings_employee_date; rows=2; shared hits=4; reads=0
```

### open_alerts

```sql
SELECT id,employee_id,shelf_id,stockout_date FROM alerts WHERE employee_id=101 AND status='OPEN' ORDER BY stockout_date DESC LIMIT 25;
```

before:

```text
Limit; rows=1; shared hits=371; reads=0
  Sort; rows=1; shared hits=371; reads=0
    Seq Scan; rows=1; shared hits=371; reads=0
```

after:

```text
Limit; rows=1; shared hits=3; reads=0
  Index Scan using idx_alerts_open_employee_date; rows=1; shared hits=3; reads=0
```

### product_inventory

```sql
SELECT inventory_id,product_id,product_quantity FROM product_inventories WHERE product_id=1;
```

before:

```text
Seq Scan; rows=10; shared hits=541; reads=0
```

after:

```text
Index Scan using idx_product_inventories_product; rows=10; shared hits=3; reads=0
```

### customer_purchases

```sql
SELECT id,date,status FROM purchases WHERE customer_id=1 ORDER BY date DESC LIMIT 25;
```

before:

```text
Limit; rows=1; shared hits=184; reads=0
  Sort; rows=1; shared hits=184; reads=0
    Seq Scan; rows=1; shared hits=184; reads=0
```

after:

```text
Limit; rows=1; shared hits=3; reads=0
  Index Scan using idx_purchases_customer_date; rows=1; shared hits=3; reads=0
```

## Índices e interpretação

- `idx_restockings_employee_date`: `restockings(employee_id,restocking_date DESC)`. Mesmas definições das quatro consultas correspondentes de ScriptSQL_Kairos_performance_indexes.sql.
- `idx_alerts_open_employee_date`: `alerts(employee_id,stockout_date DESC) WHERE status='OPEN'`. Mesmas definições das quatro consultas correspondentes de ScriptSQL_Kairos_performance_indexes.sql.
- `idx_product_inventories_product`: `product_inventories(product_id)`. Mesmas definições das quatro consultas correspondentes de ScriptSQL_Kairos_performance_indexes.sql.
- `idx_purchases_customer_date`: `purchases(customer_id,date DESC)`. Mesmas definições das quatro consultas correspondentes de ScriptSQL_Kairos_performance_indexes.sql.

O quinto índice daquele script, Employees(company_id,position), não foi avaliado por estas quatro consultas e não tem ganho certificado. Não foi criado índice redundante sobre chave UNIQUE. Em um banco Spring já existe idx_restockings_employee_week(employee_id,restocking_date DESC,id DESC), que pode cobrir a busca por funcionário/data; não instalar cegamente outro prefixo equivalente. O ensaio usou o schema de kairos-data e seus índices efetivamente listados no JSON.

Filtros de funcionário foram obtidos de registros existentes e não do exemplo employee_id=1, que é MANAGER e não tem eventos na carga. As buscas retornaram somente 2 e 1 eventos, respectivamente: alta seletividade favorece índices. O produto retornou 10 relações; o cliente, 1 compra. Esses ganhos não provam SLA de produção, não medem INSERT/UPDATE, contenção ou filtros pouco seletivos. A criação ocupa espaço e encarece escrita; isso não foi quantificado. Resultados negativos/falta de escolha de índice em outros workloads devem ser medidos separadamente.

Planos completos, tempos individuais, cardinalidades e índices: [evidence/performance_plans.json](evidence/performance_plans.json). `results_equal=true` em todas as consultas. O JSON é a evidência primária; esta tabela não contém valores estimados.

## Reprodução isolada

Na raiz de kairos-data, com Docker Desktop ligado. Use nomes novos se já existirem; nunca apague containers/volumes para repetir:

```powershell
docker run --name kairos-modelagem-bench-new --network none -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=kairos_modelagem_test -d postgres:17
docker exec kairos-modelagem-bench-new pg_isready -U postgres -d kairos_modelagem_test
# Aguardar accepting connections antes de continuar.
docker cp postgres kairos-modelagem-bench-new:/sql
docker exec kairos-modelagem-bench-new psql -U postgres -d kairos_modelagem_test -v ON_ERROR_STOP=1 -f /sql/ScriptSQL_Kairos_Criacao_Tabelas.sql -f /sql/ScriptSQL_Kairos_Triggers_Procedures_Functions.sql -f /sql/ScriptSQL_Kairos_Dataload_1M.sql -f /sql/ScriptSQL_Kairos_dau.sql -c "ANALYZE;"
docker build -f postgres/Dockerfile.validation -t kairos-modelagem-validation postgres
$repo=(Get-Location).Path
docker run --rm --network container:kairos-modelagem-bench-new -v "${repo}:/work" kairos-modelagem-validation /work/postgres/benchmark_modelagem.py --authorize-local --output /work/build/performance-repeat.json
docker stop kairos-modelagem-bench-new
```

A autenticação trust é exclusiva do container sem rede/porta. O script fixa host loopback e o nome descartável e exige --authorize-local. Ele não aceita DSN de produção. O script histórico performance_evidence_local.sql foi inspecionado, mas não executado fora do ambiente autorizado: contém DROP INDEX e não deve ser usado na Aiven. O método transacional foi reutilizado com guard, filtros não vazios e medições repetidas.
