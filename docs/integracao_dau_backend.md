# Kairos | Contrato de integração DAU com backend

Implementação realizada em `kairos-springboot`, branch `feat/dau-authenticated-activity`, em 02/11/2026. Contrato e evidências atuais abaixo; não foi aplicado no banco Aiven.

## Implementação efetiva

`DailyActivityFilter` executa dentro da cadeia Spring Security, após autenticação e antes da autorização/controller. Somente depois de uma resposta bem-sucedida (<400), usa `JwtAuthenticationToken.getToken().getSubject()` como ID. Não usa `Authentication.getName()` (que é email neste projeto), parâmetros de request, IDs em JSON ou company_id enviado pelo cliente.

`DailyActivityService` consulta os vínculos de Employees e Customers por esse ID, combina as empresas com UNION e chama `public.register_user_access` por parâmetro. Uma identidade com vínculos em duas empresas registra atividade em ambas; é uma política explícita de atividade da conta vinculada, não prova de visita a cada loja pela UI. O modelo atual permite no máximo um vínculo de cada subtipo por usuário.

O evento escolhido é **atividade autenticada**, incluindo `GET /api/v1/auth/me` e APIs comerciais; o POST de login em si, refresh, logout, cadastro, health e docs não são eventos DAU. Login inválido e requests anônimos/negados não contam. Agentes identificados por User-Agent contendo bot/crawler/spider/probe são excluídos. Isso não identifica toda automação que reutilize credenciais humanas; não há certificação antirobô.

O SQL usa `clock_timestamp()` e data de America/Sao_Paulo. UNIQUE do triplo faz upsert sem duplicar, preservando first_seen_at e atualizando last_seen_at com GREATEST para não regredir sob concorrência.

## Migração e compatibilidade

Flyway `V4__daily_active_users.sql` é incremental: cria tabela/índice se ausentes, valida colunas existentes, garante unicidade e substitui a função e as duas views DAU com a mesma assinatura/colunas. O script deste repositório contém o mesmo corpo, com BEGIN/COMMIT para uso manual. Não modificar migrations V1–V3 nem executar V4 manualmente por cima do histórico Flyway.

O teste real migrou V1–V3, instalou o SQL antigo original do kairos-data, registrou um acesso e executou V4: a linha e first_seen_at foram preservados. Também foi testado banco novo com as quatro migrations. Objetos incompatíveis, duplicações prévias ou falta de permissão devem interromper a migração para revisão, sem limpeza de dados. `CREATE OR REPLACE` requer propriedade/permissão sobre objetos preexistentes; alinhar papel Flyway e papel runtime. Não há GRANT indiscriminado para PUBLIC nem SECURITY DEFINER.

## Política de falha e observabilidade

Registro usa transação própria REQUIRES_NEW (timeout transacional 3s); falha de SQL/registro é capturada fora da transação e não muda o status/body da resposta autenticada nem reverte o negócio. WARN contém apenas o tipo de falha, sem token, email ou parâmetros. Counters: `kairos.dau.record.success` e `kairos.dau.record.failures`, sem tags de identidade. O primeiro conta chamadas bem-sucedidas, não usuários únicos.

Não há retry assíncrono/durável: uma métrica perdida só será recuperada por outra atividade válida no dia. O registro é síncrono após o controller; latência de pool/rede continua sendo limitação, não foi feito ensaio de indisponibilidade prolongada/volume. Exportação dos counters depende da configuração de observabilidade existente, que não foi alterada para expor endpoints públicos.

## Testes reais realizados

`DailyActivityPostgresIntegrationTest`: PostgreSQL Testcontainers, Flyway ativo e JPA validate, incluindo concorrência, dois usuários, dois vínculos empresariais, rejeição de vínculo inválido na função, anonimato/login inválido/probes, rollover por fixture do dia anterior, first/last, falha SQL controlada e recuperação. Um teste executa login real, assinatura/validação JWT e sessão Redis real, seguido de /auth/me, comprovando persistência sem mock de DAO. Redis de teste é novo e descartável.

Também foi corrigido InventoryMapper para preencher empresa derivada do setor e InventoryService para recusar atualização para setor de outra empresa; teste real confirma rollback da tentativa.

Resultados agregados e comandos de reprodução estão em `FINAL_MODELAGEM_REVIEW.md`. BI/Data Mart e configuração de dashboards permanecem **PENDENTE DE VALIDAÇÃO COM DANIEL**; apenas as views próprias de DAU foram mantidas neste escopo.

A função PostgreSQL `register_user_access(p_user_id INT, p_company_id INT)` registra uma vez por dia o acesso de um usuário **autenticado** a uma empresa. A mesma pessoa pode acessar várias vezes no dia sem aumentar DAU; a função atualiza `last_seen_at`.

## Contrato SQL preservado

1. Backend valida login/token e resolve o ID real do usuário (`Users.id`).
2. Backend determina a empresa autorizada com base no vínculo `Employees` ou `Customers` (não aceitar `company_id` arbitrário do cliente).
3. Após autenticação válida ou atividade que represente uso efetivo, backend executa:

```sql
SELECT register_user_access($1, $2);
```

4. BI consulta o resultado com filtro da empresa autorizada:

```sql
SELECT access_date, daily_active_users
FROM vw_dau_daily
WHERE company_id = $1
ORDER BY access_date DESC
LIMIT 30;
```

## Critérios de teste

- Dois acessos do mesmo usuário na mesma empresa no mesmo dia => DAU conta **1**.
- Dois usuários distintos na mesma empresa => DAU conta **2**.
- Vínculo usuário/empresa inexistente => a função levanta exceção.
- Um usuário legítimo em empresas distintas pode ter registro diário separado para cada empresa.
- A chamada não deve registrar probes, health checks ou tentativas de login inválidas.
- `first_seen_at` é mantido e `last_seen_at` deve se atualizar.

## Importante

- Sem evento vindo do backend, `User_Accesses` fica vazia, porque o PostgreSQL não enxerga acessos HTTP por conta própria.
- A política implementada é fail-open para a métrica, com transação isolada, WARN e counters; não há retry durável. Não é mais uma decisão de implementação pendente, mas sua latência/exportação precisa ser monitorada no deploy.
- Segurança da função envolve permissões de usuário/role no PostgreSQL além da checagem lógica do vínculo.
