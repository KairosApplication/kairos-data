# Testes executados em 02/11/2026

PostgreSQL 17 em Docker local, container `kairos-demo-sql-test`, `--network none`, sem volumes ou conexão com produção. Schema, procedures/triggers e dataload originais foram executados integralmente; depois views originais e novas views, preparação e validações. Não foram usados backups ou credenciais externos.

- Carga original: 1.000.000 registros de negócio.
- Contagens antes/depois: compras 25.000; reposições 50.000; alertas 20.000; itens 10.900. Iguais.
- Referência padrão São Paulo: 02/11/2026. Histórico distribuído em 13 dias, 20/10–01/11.
- Compras/dia: 1.923–1.924; reposições/dia: 3.846–3.847; alertas/dia: 1.538–1.539.
- Datas nulas, fora do histórico, fora da janela e futuras: zero nos quatro campos preparados.
- Cronologia de alertas, empresa da prateleira/reposição, empresa do alerta e avarias superiores à quantidade: zero problemas.
- Sete checks multiempresa do script original de modelagem: zero problemas.
- KPIs vivos: 15.000 compras concluídas, 50.000 reposições e receita 3.849.351,40.
- Cenários A/B/C/D executados com `complete_purchase`, dois produtos, +1 compra/+20 receita, histórico mantido e outras empresas idênticas. ROLLBACK confirmado.
- Asserções adicionais: IN_PROGRESS não entra; CANCELLED sai integralmente da contagem e receita. Versão final executada com sucesso.
- Segunda preparação para mesma data: NOTICE de nenhuma alteração, um registro de execução e 25.000 updates auditados (sem segunda leva).
- Banco vazio LOCAL chamado `kairosdb`, mesmo autorizado: recusado antes de tocar tabelas.
- Banco vazio LOCAL `kairos_restore` sem autorização: recusado antes de tocar tabelas.
- `git diff --check`: sem erros.

Foi necessário coletar estatísticas (`ANALYZE`) após a carga para evitar plano lento da primeira consulta. A validação completa foi repetida com sucesso após isso. Não foram medidos SLA, concorrência nem atualização visual de Power BI. A configuração real do dashboard, RLS e backend da feira ainda deve ser validada pela equipe conforme `demo_datas.md`.

Para reproduzir em ambiente local, iniciar PostgreSQL 17 sem rede e copiar a pasta `postgres` para `/sql`:

```powershell
docker run --name kairos-demo-sql-test --network none -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=kairos_demo -d postgres:17
docker cp postgres kairos-demo-sql-test:/sql
docker exec kairos-demo-sql-test psql -U postgres -d kairos_demo -v ON_ERROR_STOP=1 -f /sql/ScriptSQL_Kairos_Criacao_Tabelas.sql -f /sql/ScriptSQL_Kairos_Triggers_Procedures_Functions.sql -f /sql/ScriptSQL_Kairos_Dataload_1M.sql -f /sql/ScriptSQL_Kairos_bi_views.sql -f /sql/ScriptSQL_Kairos_Demo_KPIs.sql -c "SET kairos.demo_authorized_database='kairos_demo';" -f /sql/ScriptSQL_Kairos_Demo_Datas.sql -c 'ANALYZE;' -f /sql/ScriptSQL_Kairos_Demo_Validation.sql -f /sql/ScriptSQL_Kairos_model_validation.sql -f /sql/ScriptSQL_Kairos_Demo_Test.sql
```

Aguardar `pg_isready` antes da carga. Usar outro nome de container se já existir. O servidor fica sem porta publicada, e autenticação trust é exclusiva deste container isolado. Após terminar, pode remover somente esse container descartável com `docker rm -f kairos-demo-sql-test`.
