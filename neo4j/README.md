# Kairos - Neo4j | Grafo de responsabilidades de reposicao

## Objetivo

O PostgreSQL continua a ser a **fonte de verdade**. O Neo4j mantem uma **projecao de leitura** para consultas que percorrem multiplas relacoes: empresa -> setor -> corredor -> prateleira -> produto/alerta e funcionario -> corredor/prateleira.

**Caso de uso principal:** ao surgir um alerta em uma prateleira, listar os repositores (`STOCKER`) da mesma empresa que estao designados ao corredor ou diretamente a prateleira. O gerente (`MANAGER`) pode ver a equipe responsavel; o caixa (`CASHIER`) nao entra na lista de repositores.

Nao ha integracao automatica nem propagacao em tempo real com PostgreSQL neste MVP. Os IDs do Neo4j correspondem aos IDs originais do PostgreSQL.

### Modelo de grafo

```text
(Company)-[:HAS_SECTOR]->(Sector)-[:HAS_AISLE]->(Aisle)-[:HAS_SHELF]->(Shelf)
   ^                                        ^                          ^
   |                                        |                          |
[:WORKS_FOR]                       [:ASSIGNED_TO_AISLE]       [:ASSIGNED_TO_SHELF]
   |                                        |                          |
(Employee)----------------------------------+--------------------------+

(Shelf)-[:STOCKS {quantity}]->(Product)-[:BELONGS_TO]->(Company)
(Alert)-[:ON_SHELF]->(Shelf)
(Alert)-[:ABOUT_PRODUCT]->(Product)
```

Nodes: `Company`, `Employee`, `Sector`, `Aisle`, `Shelf`, `Product`, `Alert`. Todos possuem `id` unico. Os dados de empresa associados recebem `company_id`. Constraints e indices em `cypher/01_schema.cypher`.

## 1. Preparar no Windows / VSCode

Extraia este pacote para a **raiz** do repositorio `kairos-data`. Se ja existe `neo4j/.gitkeep`, pode mante-lo ou exclui-lo depois que houver arquivos reais.

No PowerShell:

```powershell
cd neo4j
Copy-Item .env.example .env
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

Abra `neo4j/.env` e substitua:

- `NEO4J_PASSWORD`: senha forte nova para a conta local `neo4j` (nao use `/` nessa senha).
- `KAIROS_NEO4J_API_KEY`: chave aleatoria **diferente** da senha do Neo4j, gerada pelo comando acima.
- `NEO4J_URI`: deixe `bolt://127.0.0.1:7687` para uso local.
- `POSTGRES_DSN`: configure apenas se voce for importar dados do PostgreSQL. Valores ilustrativos do `.env.example` nao funcionam sem substituicao.

**Nunca publique `.env`, senhas nem tokens.** Arquivo `.env.example` e seguro para ser versionado porque tem somente placeholders.

## 2. Iniciar o Neo4j local

O Docker Desktop deve estar aberto:

```powershell
docker compose up -d
docker compose ps
```

A primeira inicializacao pode baixar a imagem e preparar o banco. Abra o navegador:

- Neo4j Browser: http://127.0.0.1:7474
- URL de conexao: `bolt://127.0.0.1:7687`
- Usuario: `neo4j`
- Senha: a que voce colocou em `NEO4J_PASSWORD`

A imagem e `neo4j:5.26-community`, com volume persistente. As portas sao acessiveis apenas do proprio computador.

**Atenção:** trocar `NEO4J_PASSWORD` no `.env` depois de criar o volume **nao altera a senha de um banco ja inicializado**. `docker compose down -v` APAGA os dados do Neo4j; nao use para resolver senhas sem entender essa perda.

## 3. Criar schema e carregar exemplos

Ainda na pasta `neo4j/`:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m scripts.init_graph --seed
python -m scripts.smoke_test
```

`--seed` insere exemplos com IDs ficticios na faixa **990xxx**; nao le nem altera o PostgreSQL. Pode reexecutar `init_graph --seed` sem duplicar os mesmos nos e relacionamentos.

No Neo4j Browser, execute uma consulta:

```cypher
MATCH (a:Alert {id: 990061, company_id: 990001})-[:ON_SHELF]->(s:Shelf)<-[:HAS_SHELF]-(cor:Aisle)
MATCH (e:Employee {company_id: 990001, position: 'STOCKER'})
WHERE EXISTS { MATCH (e)-[:ASSIGNED_TO_AISLE]->(cor) }
   OR EXISTS { MATCH (e)-[:ASSIGNED_TO_SHELF]->(s) }
RETURN DISTINCT e.id, e.name;
```

Esperado: dois repositores, `Lucas Silva` e `Mariana Souza`. O gerente nao entra. O repositor da outra empresa tambem nao aparece. Mais consultas estao em `cypher/03_queries.cypher` (para executar manualmente, nao automaticamente).

## 4. Rodar a API de leitura

```powershell
python -m uvicorn app.main:app --reload --port 8002 --host 127.0.0.1
```

Swagger: http://127.0.0.1:8002/docs

| Metodo | Rota | Descricao |
| --- | --- | --- |
| GET | `/health` | Saude da conexao |
| GET | `/v1/companies/{company_id}/alerts/{alert_id}/stockers` | Repositores que podem atender alerta |
| GET | `/v1/companies/{company_id}/aisles/{aisle_id}/stockers` | Repositores de um corredor |
| GET | `/v1/companies/{company_id}/employees/{employee_id}/coverage` | Corredores atribuidos ao repositor |

Nos endpoints internos, use no Swagger o header `x-internal-api-key` com o valor de `KAIROS_NEO4J_API_KEY` do `.env`.

Exemplo de consulta:

```text
GET /v1/companies/990001/alerts/990061/stockers
```

A API retorna Lucas e Mariana, com a origem da atribuicao (`AISLE` ou `SHELF`). Ela e **interna e somente de leitura**: o mobile deve chamar o backend principal autenticado, que verifica a empresa e a permissao do usuario. Nunca envie a chave interna para o Android. O campo `company_id` vindo da URL **nao equivale a autenticacao do usuario**.

## 5. Opcional: importar dados reais do PostgreSQL

Execute **depois** de configurar corretamente `POSTGRES_DSN` e criar o schema. A importacao e manual, em lotes de 500 linhas, usando `MERGE` para evitar duplicidade por ID.

```powershell
python -m scripts.init_graph
python -m scripts.sync_postgres
```

Para impedir a importacao caso existam vinculos entre empresas diferentes:

```powershell
python -m scripts.sync_postgres --strict
```

O importador le (sem alterar) `Companies`, `Sectors`, `Aisles`, `Shelves`, `Employees` + `Users`, `Products`, `Employee_Aisles`, `Shelf_Employees`, `Product_Shelves`, `Alerts`. Inclui no grafo somente atribuicoes de funcionarios `STOCKER` da mesma empresa da prateleira/corredor.

**Atencao ao dataload antigo:** a formula que associa `Employee_Aisles` e `Shelf_Employees` por ID pode misturar empresas. O script `cypher/04_postgres_diagnostics.sql` detecta esses casos **no PostgreSQL**, sem alterar dados. Caso retorne valores maiores que zero, corrija **a origem** antes de confiar nos resultados da funcionalidade. O importador ignora relacionamentos invalidos e mostra a contagem.

**Limites do MVP:**

- A sincronizacao e **snapshot manual por upsert**. Alteracoes posteriores no PostgreSQL so aparecem quando rodar o comando novamente.
- Exclusoes e alteracoes de atribuicoes antigas **nao sao removidas automaticamente do Neo4j**. Para producao e necessario um mecanismo de sincronizacao consistente (eventos/outbox/CDC ou rebuild controlado).
- Os IDs ficticios 990xxx sao para demonstracao e podem coexistir com dados reais; mantenha-os separados e nao use como IDs de negocio.
- A validacao entre empresas e reforcada pelo importador, mas a autenticacao/autorizacao real deve ser feita no backend principal, nao so nesta API.

## 6. Subir ao GitHub

De volta a raiz do repositorio (depois de verificar sua branch atual):

```powershell
cd ..
git status
git add neo4j/
git status
```

Confirme que **`neo4j/.env` e `neo4j/.venv/` NAO aparecem**. Depois:

```powershell
git commit -m "feat: adiciona grafo neo4j de responsabilidades de reposicao"
git push
```

Se a branch for nova, use `git push -u origin NOME_DA_BRANCH` e abra um PR para `main`. Evite enviar diretamente a `main` protegida.
