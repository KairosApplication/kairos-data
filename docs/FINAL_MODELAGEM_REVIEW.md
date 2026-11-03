# Revisão final de Modelagem — Kairos

Data: 02/11/2026. Repositórios: kairos-data (`feat/modelagem-final-validation`) e kairos-springboot (`feat/dau-authenticated-activity`). Parecer: **APROVADA COM RESSALVAS**. Este parecer não certifica 3FN integral nem isolamento multiempresa universal.

## A. Resumo executivo

O DAU deixou de ser somente SQL: o backend registra uso autenticado com identidade do JWT validado, empresa resolvida pelos vínculos persistidos e upsert concorrente. A suíte completa passou em PostgreSQL e Redis reais: 251 testes, zero falhas, erros ou ignorados. Checkstyle, SpotBugs e cobertura passaram.

A auditoria encontrou problemas reais: sete escritas entre empresas distintas são aceitas pelas FKs atuais; a carga antiga tinha 5.344 alertas resolvidos antes da abertura; o mapper de inventário omitia empresa obrigatória. Foram corrigidos o mapper, a mudança de setor entre empresas no serviço e a cronologia de novas cargas fictícias. A decomposição do modelo exige migração coordenada e permanece pendente, conforme permitido pelo escopo. Não houve acesso à Aiven, produção ou demonstração compartilhada.

| Área | Situação encontrada | Entrega / situação final |
|---|---|---|
| DAU | SQL sem coleta autenticada comprovada | Integração real, V4 compatível e testes aprovados; deploy pendente de revisão |
| Normalização | Revisão preliminar | Dependências/cardinalidades documentadas; 3FN integral não comprovada |
| Multiempresa | FKs isoladas | Lacunas reproduzidas; correção de inventário no backend; enforcement geral pendente |
| Carga | Comentário 1M e datas inconsistentes | Total real 1.050.000 documentado; novas cargas sem os 5.344 erros |
| Performance | Índices propostos | Quatro comparações reais com resultados iguais e planos completos |
| Rotinas / auditoria / catálogo | Artefatos existentes | Smoke tests reais e catálogo idempotente verificados |
| BI / Power BI | Escopo do Daniel | Não alterado; validação com Daniel pendente |

## B. DAU

No Spring, `DailyActivityFilter` é inserido antes do AuthorizationFilter, após a autenticação existente. Registra somente respostas de sucesso (<400) em API autenticada. `DailyActivityService` usa transação independente e deriva empresas de Employees/Customers a partir do subject numérico do JWT. Parâmetros de usuário/empresa fornecidos pelo cliente não definem o registro.

Login isolado não conta; `/api/v1/auth/me` ou uso de negócio autenticado conta. Anônimos, login inválido, health e User-Agents conhecidos de bots ficam fora. A heurística de User-Agent não detecta todos os robôs. Usuário ligado a duas empresas conta em ambas: a métrica representa atividade dos membros, não comprova visita individual a cada loja.

V4 cria/valida `User_Accesses`, UNIQUE(user_id,company_id,access_date), índice empresa/data, função e duas views exclusivas de DAU. Instalação sobre o script antigo foi testada preservando registro e first_seen_at. Data usa America/Sao_Paulo; o upsert conserva first_seen_at e avança last_seen_at com GREATEST. A função recusa vínculo inexistente. Executa com privilégios do chamador; não há SECURITY DEFINER ou autorização de acesso por parâmetros HTTP.

Falha de coleta não invalida a operação de negócio: WARN sem PII e contador de falhas. Não há fila durável/retry. Coleta síncrona pode adicionar latência de pool/rede, mesmo com timeout transacional. Permissões e deploy reais não foram executados.

Arquivos Spring: `security/DailyActivityFilter.java`, `service/DailyActivityService.java`, `config/SecurityConfig.java`, `db/migration/V4__daily_active_users.sql`, `DailyActivityPostgresIntegrationTest.java`, `FlywaySchemaIntegrationTest.java`, fixture SQL legada e `docs/dau.md`. O SQL independente em kairos-data acompanha a V4, com BEGIN/COMMIT. Política completa: [integracao_dau_backend.md](integracao_dau_backend.md).

Nove testes DAU passaram: repetição sem duplicação e sem aceitar IDs forjados; dois usuários; vínculo inválido/múltiplas empresas; exclusões; vinte requisições concorrentes; dois dias; falha SQL sem derrubar /me e recuperação; criação de inventário com empresa e bloqueio de mudança entre empresas; login real/JWT real/sessão Redis real seguido de Bearer /me. Dois testes Flyway passaram, incluindo compatibilidade com instalação legada.

## C. Normalização

[normalizacao_cardinalidades.md](normalizacao_cardinalidades.md) registra chaves candidatas, dependências funcionais, cardinalidades e avaliação por tabela. 1FN é compatível com os atributos comerciais escalares; JSON de auditoria é snapshot histórico, não relação comercial desmembrada. Chaves artificiais não provam 2FN/3FN.

Há redundância condicional setor → empresa em Inventories, categoria → empresa em Products e tabela → descrição de tabela no catálogo. NULLs e a possível existência de inventário sem setor precisam de decisão de negócio. Não se certifica a 3FN desses casos nem se remove empresa sem analisar autorização, ORM e consumidores.

Correções seguras: mapper deriva empresa do setor; atualização de inventário recusa setor de outra empresa; carga corrige somente novas datas fictícias. Não foi feita decomposição destrutiva. Estratégia pendente: definir invariantes, migrar por expansão/contração, reconciliar dados, impor coerência também em UPDATE de pais/filhos e coordenar contratos. CHECK/trigger não remove dependência transitiva por si só.

Divergências ORM/DDL preexistentes: Category não mapeia company_id obrigatório; Sector.name é globalmente único no JPA e por empresa no DDL; Product.name é único no JPA e não no DDL; Product.category é obrigatória no JPA e opcional no DDL. O CRUD completo desses módulos não está certificado. Corrigir exige mudanças coordenadas de serviços, escopo/cache e migrações.

## D. Integridade multiempresa

No banco corrigido, os 13 diagnósticos de `ScriptSQL_Kairos_model_validation.sql` retornaram zero. Isso prova consistência daquela carga, não que futuras escritas incoerentes sejam impedidas.

`test_company_constraints_local.sql` tentou sete escritas incoerentes: produto/categoria, inventário/setor, produto/inventário, funcionário/corredor, reposição, item de compra/empresa do cliente e produto/prateleira. **Todas as sete foram aceitas pelo PostgreSQL**, dentro de transação revertida. São falhas de enforcement reproduzidas, não sete proteções aprovadas.

O backend agora preenche empresa de inventário e bloqueia mudança para setor de outra empresa com 403, mantendo o vínculo original. Procedure de reposição e controles do serviço verificam vínculos, mas não impedem SQL direto. Ainda é necessário impor invariantes gerais no banco e cobrir alterações dos pais, concorrência e todos os endpoints. Nenhuma constraint empresarial universal foi anunciada como concluída.

## E. Performance

PostgreSQL 17.11, carga real 1.050.000, contêiner sem rede/porta, ANALYZE, duas execuções de aquecimento e sete medidas por cenário. Mesmas consultas e resultados antes/depois; índices opcionais criados/retirados em transação revertida. Lista original de índices restaurada e comparada.

| Consulta | Mediana antes → depois (ms) | Shared hits antes → depois | Linhas |
|---|---|---|---:|
| Reposições por funcionário/data | 2.147 → 0.012 | 417 → 4 | 2 |
| Alertas OPEN por funcionário/data | 1.260 → 0.014 | 371 → 3 | 1 |
| Relações por produto | 4.168 → 0.011 | 541 → 3 | 10 |
| Compras por cliente/data | 0.945 → 0.009 | 184 → 3 | 1 |

Seq Scan (e Sort quando aplicável) tornou-se Index Scan; reads=0 em todos os casos, cache aquecido. Não houve Bitmap Scan nesses planos. Não é SLA de produção nem medição de disco frio, escrita ou alta concorrência. O quinto índice proposto (Employees) não foi medido. Índice Spring V3 por funcionário/data/id pode tornar outro prefixo redundante: não instalar cegamente.

SQL, planos e reprodução: [performance_final.md](performance_final.md). Evidência primária: [performance_plans.json](evidence/performance_plans.json). Benchmark novo: `postgres/benchmark_modelagem.py`, guardado para loopback e banco descartável, com comparação dos resultados e rollback de DDL.

## F. Requisitos existentes

| Requisito | Situação | Evidência / limite |
|---|---|---|
| DAU autenticado, concorrência, histórico | CONCLUÍDO | 9 testes reais, UNIQUE, upsert, fuso e vínculos |
| Migração DAU sobre schema anterior | CONCLUÍDO | 2 testes Flyway, incluindo script legado |
| Deploy DAU e permissões reais | PENDENTE | Não autorizado/executado em banco compartilhado |
| Cardinalidades e análise 1FN/2FN/3FN | CONCLUÍDO COM RESSALVAS | Análise por tabela entregue; decomposição e certificação integral pendentes |
| Integridade multiempresa geral | PENDENTE | Sete escritas adversariais aceitas |
| Inventário: empresa e troca de setor | CONCLUÍDO | Correção e teste real de criação/403 |
| Dataload e cronologia | CONCLUÍDO | Carga nova 1.050.000; 13 checks zero |
| Índices / EXPLAIN ANALYZE BUFFERS | CONCLUÍDO COM RESSALVAS | Quatro cenários medidos; cache quente e alta seletividade |
| Functions / procedures | CONCLUÍDO COM RESSALVAS | Reposição, disponibilidade e fechamento/total de compra testados; não todos os cenários adversariais |
| Trigger de auditoria | CONCLUÍDO | INSERT/UPDATE/DELETE, OLD/NEW/TG_OP/CURRENT_USER verificados |
| Catálogo | CONCLUÍDO COM RESSALVAS | Duas execuções, 111 linhas distintas em ambas; classificação não impõe GRANT/RLS |
| CTE / recursividade / window functions | CONCLUÍDO COM RESSALVAS | Artefatos existentes inspecionados; validação analítica pertence ao Daniel |
| Backup e recuperação | CONCLUÍDO COM RESSALVAS | Evidência histórica de 26/10 em backup_recuperacao.md; não repetido nesta tarefa |
| RPA interdisciplinar | CONCLUÍDO COM RESSALVAS | Histórico informado de PRs aprovadas; não reexecutado nem refeito |
| Data Mart / Star / Snowflake / Power BI / KPIs BI | SOB RESPONSABILIDADE DO DANIEL | PENDENTE DE VALIDAÇÃO COM DANIEL; arquivos não alterados |

## G. Segurança

Testes SQL usaram somente `kairos-modelagem-postgres` e `kairos-modelagem-fixed`, PostgreSQLs novos com `--network none`, sem portas publicadas, banco `kairos_modelagem_test`. Testcontainers criou PostgreSQL/Redis próprios para a suíte. Não foram usados kairosdb, kairos_demo compartilhado ou credenciais Aiven. Trust é restrito ao contêiner isolado de ensaio, não recomendação de deploy.

Os testes adversariais e de rotinas fazem ROLLBACK; sequências podem avançar no banco descartável. Os scripts de diagnóstico local contêm escritas e não devem ser usados na Aiven. Nenhum volume existente foi apagado. Serviços locais preexistentes foram preservados. Fixtures são fictícias. Logs brutos ficam em build ignorado; JSON versionado contém somente métricas/planos e resumo de suítes, sem properties ou credenciais.

Ausência de RLS/constraints compostas gerais permanece risco real de integridade. Catálogo não é mecanismo de autorização. Deploy e acesso de runtime exigem revisão de privilégios; superusuário de teste não certifica grants de produção.

## H. Testes

Na raiz de kairos-springboot, Docker Desktop ligado, comando efetivamente aprovado em PowerShell:

```powershell
$repoPath=(Get-Location).Path
docker run --rm --name kairos-modelagem-maven -v "${repoPath}:/app" -v kairos-modelagem-audit-m2:/root/.m2 -v /var/run/docker.sock:/var/run/docker.sock -e TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal -w /app maven:3.9-eclipse-temurin-21 mvn -B -Ppostgres-tests '-Dintegration.redis=true' '-Dintegration.redis.container=true' verify
```

| Teste | Comando / procedimento | Resultado e evidência |
|---|---|---|
| Suíte Java completa | Comando acima | 251 aprovados, 0 falhas, 0 erros, 0 ignorados; backend_tests.json |
| DAU PostgreSQL | DailyActivityPostgresIntegrationTest incluído acima | 9 aprovados, com login/JWT/Redis reais |
| Migração Flyway | FlywaySchemaIntegrationTest incluído acima | 2 aprovados; row e first_seen legados preservados |
| Qualidade Java | Fase verify acima | Checkstyle 0; SpotBugs 0; JaCoCo 9.515/10.417 instruções (91,34%); gates aprovados |
| Consistência carga | psql -v ON_ERROR_STOP=1 -f /sql/ScriptSQL_Kairos_model_validation.sql | 13 diagnósticos zero na carga corrigida; carga anterior tinha 5.344 erros de cronologia |
| Escritas entre empresas | psql -v ON_ERROR_STOP=1 -f /sql/test_company_constraints_local.sql | 7 aceitas: lacunas conhecidas, rollback |
| Rotinas e auditoria | psql -v ON_ERROR_STOP=1 -f /sql/test_modelagem_routines_local.sql | Assertions aprovadas; rollback; contagens e estoque preservados |
| Catálogo idempotente | psql -v ON_ERROR_STOP=1 -f /sql/ScriptSQL_Kairos_data_catalog.sql, duas vezes | 111 linhas e 111 pares distintos em ambas |
| Performance | benchmark_modelagem.py --authorize-local --output ... | Quatro results_equal=true, planos reais e índices restaurados; JSON versionado |
| Validação estática kairos-data | PYTHONPATH=build/ci-tools; python .github/scripts/validate.py | 42 arquivos estruturados/fontes validados; sem executar aplicações ou acessar serviços |

A imagem reproduzível `postgres/Dockerfile.validation` também foi compilada com sucesso. Backend publicado no commit `72cca67`, branch `feat/dau-authenticated-activity`.

Para SQL, o prefixo real é `docker exec kairos-modelagem-fixed psql -U postgres -d kairos_modelagem_test`; antes foi feito `docker cp postgres kairos-modelagem-fixed:/sql`. Criação/carga isolada e comando exato do benchmark estão em performance_final.md. Não executar esses testes contra um banco compartilhado.

Histórico de problemas: regressão inicial teve 1 falha no teste de inventário, cujos setores não possuíam empresa; fixture corrigida para cumprir o DDL real, sem remover bloqueio. Verify intermediário teve 1 alerta SpotBugs por armazenar MeterRegistry; passou a guardar apenas Counter. Uma invocação PowerShell com flags -D sem aspas falhou antes dos testes; comando acima corrigido. O resultado final substitui esses resultados, mas não os oculta. Logs locais: build/modelagem-complete-verify.log no Spring; JSON sanitizado: [backend_tests.json](evidence/backend_tests.json).

## I. Pendências restantes

1. **P0:** definir e implementar enforcement multiempresa geral, cobrindo escritas SQL e UPDATE dos pais/filhos, concorrência e endpoints ainda não certificados; corrigir Category.company_id e divergências ORM/DDL coordenadamente.
2. **P1:** aprovar regras para setor/categoria opcionais e executar migração de normalização por expansão/contração; somente então certificar 3FN dos casos pendentes.
3. **P1:** revisar/mergear as duas PRs, validar privilégios de runtime e autorizar deploy DAU no ambiente escolhido. Nenhum deploy foi realizado nesta tarefa.
4. **P2:** medir índices em workload menos seletivo e escrita, avaliar redundância com V3 Spring e monitorar latência/perdas de coleta DAU antes de adoção ampla.

Validação BI/Data Mart/Power BI permanece com Daniel, fora das pendências sob nossa responsabilidade.

## J. Parecer final

**APROVADA COM RESSALVAS.** Integração DAU, compatibilidade de migração, correções limitadas, ensaio de performance e evidências estão disponíveis para revisão e entrega. A suíte real passou. A modelagem integral ainda não pode ser declarada totalmente normalizada ou universalmente isolada por empresa: há sete contraexemplos reproduzidos e divergências ORM/DDL documentadas. Entregar este relatório como auditoria transparente é possível; declarar todos os requisitos integralmente encerrados não é sustentado pelos testes.
