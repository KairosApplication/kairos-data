# Kairos - API Redis de histórico semanal de reposições

Microserviço interno **FastAPI + Redis** para exibir rapidamente no mobile o histórico da **semana atual** de cada repositor. Criado a partir do requisito discutido com Davi Dias.

**O PostgreSQL (`Restockings`) é o registro oficial e permanente.** Redis apenas guarda uma cópia temporária da semana. Dados antigos devem ser consultados no PostgreSQL. Não use Redis como único armazenamento de reposições.

## Estrutura

```text
redis/
├── .env.example
├── requirements.txt
├── requirements-dev.txt
├── docker-compose.yml
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── schemas.py
│   ├── store.py
│   └── time_utils.py
└── tests/
    ├── test_api.py
    └── test_week.py
```

## Como funciona

1. O backend do Kairos registra uma reposição no PostgreSQL, na tabela `Restockings`.
2. **Somente depois de confirmar a transação**, o backend envia o registro para `POST /v1/restockings/events` desta API interna. O envio deve usar o ID real da reposição.
3. A API usa Redis **LIST** (`LPUSH`, `LRANGE`) por empresa, repositor e semana, mantendo as reposições mais recentes primeiro.
4. O Redis usa `EXPIREAT` para apagar o cache no **início da próxima segunda-feira, à meia-noite no horário de São Paulo**.
5. Se o backend reenviar o mesmo `restocking_id`, o cache ignora a duplicata (operação atômica via Lua).
6. Para mostrar o histórico, o mobile chama o **backend autenticado** do Kairos, que consulta `GET /v1/restockings/week` na API Redis. **Não coloque a chave interna no APK/mobile.**

Exemplo de chave:

```text
kairos:company:5:stocker:72:week:2026-10-12:restockings
```

O cache armazena **até 500 reposições por funcionário por semana** por padrão (configurável). Se precisar listar tudo ou recuperar semanas anteriores, consultar PostgreSQL.

## Instalação no Windows (terminal VSCode / PowerShell)

A partir da pasta `redis/`:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

Edite o `.env` e coloque uma chave interna forte e exclusiva (não commitar). Para gerar uma:

```powershell
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

Se **ainda não tiver Redis rodando** localmente, inicie com Docker:

```powershell
docker compose up -d
```

Se já existir Redis acessível em `localhost:6379`, **não suba outro container**. Atualize `REDIS_URL` no `.env` conforme necessário.

Inicie a API:

```powershell
python -m uvicorn app.main:app --reload --port 8001
```

Acesse a documentação Swagger em `http://127.0.0.1:8001/docs`.

## Endpoints

| Método | Rota | Uso |
|---|---|---|
| `GET` | `/health` | Confere a conexão com Redis |
| `POST` | `/v1/restockings/events` | Adiciona reposição já salva no PostgreSQL |
| `GET` | `/v1/restockings/week?company_id=5&employee_id=72&limit=100` | Retorna histórico da semana atual |

As duas rotas `/v1/...` exigem header `X-Internal-API-Key`, configurado em `KAIROS_INTERNAL_API_KEY`.

### POST `/v1/restockings/events`

```json
{
  "restocking_id": 991,
  "company_id": 5,
  "employee_id": 72,
  "product_id": 10,
  "shelf_id": 4,
  "inventory_id": 3,
  "restocked_quantity": 30,
  "qnt_avarias": 2,
  "restocking_date": "2026-10-16T10:30:00-03:00",
  "product_name": "Arroz Integral"
}
```

Os dados de exemplo são fictícios. `restocking_date` exige fuso horário. O POST aceita **apenas eventos da semana atual**, conforme horário do servidor. Isso evita recriar chaves de semanas antigas no cache. Para registros antigos, use PostgreSQL.

Resposta típica:

```json
{
  "cached": true,
  "duplicate": false,
  "week_start": "2026-10-12T00:00:00-03:00",
  "expires_at": "2026-10-19T00:00:00-03:00"
}
```

Um reenvio com mesmo `restocking_id` retorna `cached: false` e `duplicate: true`.

### GET `/v1/restockings/week`

Exemplo: `/v1/restockings/week?company_id=5&employee_id=72&limit=100`

```json
{
  "company_id": 5,
  "employee_id": 72,
  "week_start": "2026-10-12T00:00:00-03:00",
  "week_end": "2026-10-19T00:00:00-03:00",
  "total_cached": 1,
  "items": [
    {
      "restocking_id": 991,
      "company_id": 5,
      "employee_id": 72,
      "product_id": 10,
      "shelf_id": 4,
      "inventory_id": 3,
      "restocked_quantity": 30,
      "qnt_avarias": 2,
      "restocking_date": "2026-10-16T10:30:00-03:00",
      "product_name": "Arroz Integral"
    }
  ]
}
```

## Integração com o PostgreSQL

A tabela atual `Restockings` já possui `id`, `inventory_id`, `employee_id`, `shelf_id`, `restocking_date`, `restocked_quantity`, `qnt_avarias` e `product_id`. Para `company_id`, fazer JOIN com `Employees`/`Inventories` e validar que os registros pertencem à mesma empresa. `product_name` vem da tabela `Products`, opcional no payload.

Exemplo de consulta de uma reposição já registrada, para o backend montar o evento:

```sql
SELECT
    r.id AS restocking_id,
    e.company_id,
    r.employee_id,
    r.inventory_id,
    r.shelf_id,
    r.product_id,
    r.restocked_quantity,
    r.qnt_avarias,
    r.restocking_date AT TIME ZONE 'America/Sao_Paulo' AS restocking_date,
    p.name AS product_name
FROM Restockings r
JOIN Employees e ON e.id = r.employee_id
JOIN Products p ON p.id = r.product_id AND p.company_id = e.company_id
JOIN Inventories i ON i.id = r.inventory_id AND i.company_id = e.company_id
WHERE r.id = :restocking_id;
```

O resultado precisa ser serializado como JSON com fuso horário explícito, por exemplo `-03:00` ou `Z`. Validar também o vínculo de empresa da prateleira caso o backend permita cadastrar dados manualmente.

**Ponto pendente:** a procedure atual `perform_restocking` não devolve diretamente o `id` gerado. A equipe de backend deve definir como obter de forma segura o registro persistido (por exemplo, adaptar procedure para devolver o ID), e disparar o evento só após o commit. Não inferir `id` com `MAX(id)`.

**Falhas de integração:** se o PostgreSQL confirmar e o Redis/API falhar, o registro permanente continua no PostgreSQL. O backend deve registrar a falha e ter estratégia de reenvio, ou reconstruir o cache da semana a partir de `Restockings`. Redis vazio **não significa** ausência de reposições registradas no banco.

## Segurança

- Não expor a API Redis diretamente ao aplicativo mobile. Autenticação de funcionários, autorização por empresa e cargo (`STOCKER`, `MANAGER`, `CASHIER`) ficam no backend do Kairos.
- A API interna usa chave de serviço como proteção adicional, mas isso não substitui o controle de acesso do backend.
- Não colocar `.env`, Redis URL autenticada ou chaves internas no GitHub.
- A integração de produção deve usar rede privada/TLS (`rediss://`) conforme o ambiente.
- A API não executa inserts no PostgreSQL; recebe apenas notificações de reposições já gravadas.

## Teste manual pelo PowerShell (dados fictícios)

Com a API rodando e uma chave interna válida no `.env`, use uma chave de teste local. **Este exemplo apenas simula a chegada de um evento no Redis; não grava no PostgreSQL.**

```powershell
$key = "COLOQUE_A_CHAVE_DO_SEU_ENV_AQUI"
$headers = @{ "X-Internal-API-Key" = $key }
$body = @{
  restocking_id = 991
  company_id = 5
  employee_id = 72
  product_id = 10
  inventory_id = 3
  shelf_id = 4
  restocked_quantity = 30
  qnt_avarias = 2
  restocking_date = [DateTimeOffset]::Now.ToString("o")
  product_name = "Arroz Integral"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://127.0.0.1:8001/v1/restockings/events" `
  -Method Post -Headers $headers -Body $body -ContentType "application/json"

Invoke-RestMethod -Uri "http://127.0.0.1:8001/v1/restockings/week?company_id=5&employee_id=72" `
  -Headers $headers
```

## Testes

```powershell
pip install -r requirements-dev.txt
python -m pytest -q
```

Os testes cobrem a virada de semana, isolamento por empresa, duplicação de eventos e autenticação interna.
