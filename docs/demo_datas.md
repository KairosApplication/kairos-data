# Demonstração de 02/11/2026

Use apenas uma cópia descartável já restaurada (`kairos_demo` ou `kairos_restore`). Não use conexão, credenciais nem endpoint Aiven de produção. Nenhuma conexão de produção é necessária. Os comandos abaixo pressupõem serviço libpq local `kairos_demo_local` apontando explicitamente para a cópia; configure host/porta/usuário locais, sem guardar senha no Git.

```powershell
psql 'service=kairos_demo_local' -X -v ON_ERROR_STOP=1 -f postgres/ScriptSQL_Kairos_bi_views.sql
psql 'service=kairos_demo_local' -X -v ON_ERROR_STOP=1 -f postgres/ScriptSQL_Kairos_Demo_KPIs.sql
psql 'service=kairos_demo_local' -X -v ON_ERROR_STOP=1 -c "SET kairos.demo_authorized_database='kairos_demo'; SET kairos.demo_reference_date='2026-11-02';" -f postgres/ScriptSQL_Kairos_Demo_Datas.sql
psql 'service=kairos_demo_local' -X -v ON_ERROR_STOP=1 -f postgres/ScriptSQL_Kairos_Demo_Validation.sql -f postgres/ScriptSQL_Kairos_model_validation.sql
psql 'service=kairos_demo_local' -X -v ON_ERROR_STOP=1 -c "SET kairos.demo_authorized_database='kairos_demo';" -f postgres/ScriptSQL_Kairos_Demo_Test.sql
```

Para `kairos_restore`, ajuste também a autorização. Omita o segundo SET para usar a data da execução em São Paulo. No pgAdmin/DBeaver, use a mesma sessão para os SETs e o script. A transação falha antes dos UPDATEs se a base não estiver autorizada. A autorização é uma trava contra enganos, não substitui controle de acesso. Pare as escritas do backend durante a preparação; os locks bloqueiam operações concorrentes. O script atualiza só quatro campos temporais; auditoria permanece ativa e acrescenta registros em Audits. Não recarrega o milhão de linhas.

O histórico fica em 20/10–01/11 quando a referência é 02/11; a janela viva inclui 20/10–02/11. Horários ficam entre 08h e 22h. Alertas resolvidos têm resolução no mesmo dia, após 09h; resoluções existentes de cancelados são preservadas como resoluções, com datas corrigidas. Uma segunda execução para a mesma referência não toca em nenhum registro, inclusive operações novas. Outra referência exige nova cópia restaurada. Não apague o controle `kairos_demo_date_runs` para reutilizar uma cópia em uso.

## Conferência

Após restaurar a carga e preparar as datas, execute `ANALYZE;` na cópia antes de conectar os dashboards. No teste local, estatísticas ainda não coletadas após a carga tornaram a primeira consulta lenta; com estatísticas atualizadas, a validação completa e o teste integrado terminaram em cerca de dois segundos. Esse tempo não é garantia para o ambiente da feira.

```sql
SELECT * FROM vw_bi_demo_window;
SELECT * FROM kairos_demo_date_runs; -- before_counts = after_counts
SELECT * FROM vw_bi_sales_14d WHERE company_id = 1 ORDER BY date_key;
SELECT * FROM vw_bi_restockings_14d WHERE company_id = 1 ORDER BY date_key;
```

Imediatamente após preparar: 13 dias distribuídos nas três tabelas, `outside_history`, `outside_window`, `null_dates`, `future_dates` e todos os checks `problems` iguais a zero (referência de hoje). Se usar data futura de referência, future_dates é esperado, mas os KPIs vivos continuam relativos ao dia real. Depois de novas operações, `today_operations` cresce e `outside_history` pode crescer; não é erro. Compare contagens atuais com o registro inicial antes de demonstrar; após a demonstração há novas operações legítimas. Execute também a validação de modelagem: qualquer inconsistência preexistente requer revisão, não é corrigida pelo ajuste temporal.

## Configuração do Daniel

Não há dashboard/arquivo Power BI neste repositório; modo de conexão e atualização automática não puderam ser verificados. Conectar o dashboard **e o backend de demonstração** à mesma cópia. Configurar timezone das conexões/backend para `America/Sao_Paulo`: o schema usa TIMESTAMP sem fuso e os defaults/procedures dependem da sessão. SQL não força a atualização do relatório.

Consumir `vw_bi_sales_14d` e `vw_bi_restockings_14d`, agrupadas por empresa/dia, com soma das métricas. No Power BI, usar DirectQuery e atualização automática da página no intervalo suportado pela capacidade/licença; confirmar com operação real e refresh visual. Em Import, novas linhas só aparecem após atualização do dataset, portanto não prometer tempo real. Desativar filtros fixos de 2025/2026 e caches que impeçam a atualização; não somar acumulados de ranking como métricas diárias. As views mensal e semanal existentes permanecem intactas. A dimensão data existente inclui hoje assim que houver operação; para mostrar dias vazios, usar calendário contínuo no BI.

Aplicar RLS de empresa vinculado à identidade autenticada (ou autorização equivalente no backend). Filtro visual/company_id nas views não garante isolamento: não distribuir acesso SQL irrestrito às tabelas para clientes. Testar usuário A sem acesso à empresa B antes de expor a demo. As novas views não implementam autenticação.

Vendas contam só COMPLETED; receita soma itens e compras são contadas uma vez pelo cabeçalho. A carga original tem 25 mil compras e só 10.900 itens; compras concluídas sem itens aparecem em `purchases_without_items`, sem receita inventada. A distribuição original de status também deixa algumas empresas sem vendas concluídas; escolher uma empresa com vendas para a feira (por exemplo 1) e conferir os dados. Reposições somam quantidade bruta, avarias e líquido separadamente.

Redis aceita eventos da semana atual; não enviar o histórico inteiro para o cache e não reutilizar chaves de produção. Para histórico de 14 dias consultar PostgreSQL. Neo4j copia `stockout_date`: se necessário, sincronizar somente instância demo após a preparação com configuração própria. Não alterar Redis, MongoDB ou Neo4j de produção. A preparação não executa sincronizações.

O teste reversível usa `complete_purchase`, dois itens, estoque real da cópia e ROLLBACK; valida +1 compra/+20 receita, histórico e métricas idênticas das demais empresas. Sequences podem avançar apesar do rollback. Não executá-lo em produção.
