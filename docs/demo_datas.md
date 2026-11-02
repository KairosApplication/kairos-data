# Demonstração de 02/11/2026

## Começar do zero no pgAdmin (sem backup e sem acessar Aiven)

O banco novo vazio pode ser populado com os dados fictícios do projeto. Isso cria um ambiente equivalente para demonstração; não copia operações reais, senhas ou usuários atuais da Aiven. O procedimento de cópia fiel por backup já existe em `backup_recuperacao.md`, mas não é necessário neste caminho.

1. Use um servidor PostgreSQL **local ou exclusivo de demonstração**, não o servidor Aiven de produção. Se o `kairos_demo` criado anteriormente estiver dentro do servidor Aiven compartilhado, deixe-o como está e use o servidor local abaixo.
2. Se não houver PostgreSQL local e houver Docker Desktop, execute no PowerShell (senha exclusiva local, não a senha Aiven):

   ```powershell
   $demoSecret = Read-Host 'Crie uma senha apenas para o PostgreSQL local' -AsSecureString
   $env:POSTGRES_PASSWORD = [System.Net.NetworkCredential]::new('', $demoSecret).Password
   docker run --name kairos-demo-local -p 127.0.0.1:55432:5432 -e POSTGRES_PASSWORD -e POSTGRES_DB=kairos_demo -d postgres:17
   Remove-Item Env:POSTGRES_PASSWORD
   docker exec kairos-demo-local pg_isready -U postgres -d kairos_demo
   ```

   Aguarde `accepting connections`. Se o nome/porta já estiver ocupado, não remova containers existentes; escolha outro nome/porta e ajuste as conexões abaixo. Sem Docker, use instalação local do PostgreSQL e crie `kairos_demo` vazio em Databases → Create → Database.
3. No pgAdmin: Servers → Register → Server. Nome **Kairos DEMO LOCAL**; Connection: Host `127.0.0.1`, Port `55432`, Maintenance database `kairos_demo`, Username `postgres`, Password a senha local criada. Para PostgreSQL instalado diretamente, use a porta/usuário locais configurados.
4. Expanda **Kairos DEMO LOCAL → Databases → kairos_demo**, clique com o botão direito em **kairos_demo → Query Tool**. Confira `SELECT current_database(), inet_server_addr(), inet_server_port();`. Deve retornar `kairos_demo`; confira também o servidor/porta na conexão do pgAdmin (a porta interna no SELECT será 5432 no Docker).
5. Na pasta do repositório, gere o arquivo único para o pgAdmin:

   ```powershell
   New-Item -ItemType Directory -Path build -Force | Out-Null
   python postgres/build_demo_setup.py --output build/kairos_demo_setup.sql
   ```

   O gerador não conecta a nenhum banco e recusa sobrescrever arquivo existente. Para gerar novamente, use outro nome de saída.
6. Na aba de **kairos_demo**, abra `build/kairos_demo_setup.sql` (ícone de pasta). Sem selecionar um trecho, execute o arquivo inteiro. O arquivo verifica o nome do banco e exige schema public vazio, cria tabelas/rotinas, carrega os dados, cria views, autoriza a sessão, prepara datas de hoje, executa ANALYZE e validações. Não execute novamente em banco populado. Se houver erro, pare, execute `ROLLBACK;` e confira o erro antes de continuar.
7. Confira as validações abaixo. Opcionalmente execute `ScriptSQL_Kairos_Demo_Test.sql` nessa mesma sessão; ele reverte a compra criada. Nenhuma ação é realizada na Aiven.

### Alternativa: abrir os arquivos um por vez

Sempre no Query Tool do **kairos_demo local vazio**, execute nesta ordem:

1. `ScriptSQL_Kairos_Criacao_Tabelas.sql`
2. `ScriptSQL_Kairos_Triggers_Procedures_Functions.sql`
3. `ScriptSQL_Kairos_Dataload_1M.sql` (aguarde concluir)
4. `ScriptSQL_Kairos_bi_views.sql`
5. `ScriptSQL_Kairos_Demo_KPIs.sql`
6. `SET kairos.demo_authorized_database = 'kairos_demo';` e, na mesma conexão, `ScriptSQL_Kairos_Demo_Datas.sql`
7. `ANALYZE;`
8. `ScriptSQL_Kairos_Demo_Validation.sql`
9. `ScriptSQL_Kairos_model_validation.sql`
10. Opcional: `ScriptSQL_Kairos_Demo_Test.sql` na mesma sessão autorizada.

Os três primeiros scripts originais não têm a trava da demo; por isso o arquivo único gerado é preferível. A carga original desativa apenas os dois triggers de auditoria durante o seed fictício para manter o milhão de linhas e os reativa ao final; a preparação temporal mantém os triggers ativos. Se já restaurou uma cópia populada, pule os três primeiros passos e use apenas views/preparação/validações. Não misture restauração e carga na mesma base.

### Backend Spring Boot e acesso na feira

Este repositório não contém Java, pom.xml, application.properties/yml nem dashboard. Não foi possível verificar a configuração efetiva desses projetos. Exemplo para Spring Boot com datasource padrão/Hikari (aplicar apenas na instância demo, não no deploy de produção):

```powershell
$env:SPRING_DATASOURCE_URL='jdbc:postgresql://127.0.0.1:55432/kairos_demo'
$env:SPRING_DATASOURCE_USERNAME='postgres'
# Defina SPRING_DATASOURCE_PASSWORD com a senha local na IDE/gerenciador de segredos.
$env:SPRING_DATASOURCE_HIKARI_CONNECTION_INIT_SQL="SET TIME ZONE 'America/Sao_Paulo'"
$env:SPRING_JPA_HIBERNATE_DDL_AUTO='validate'
$env:SPRING_SQL_INIT_MODE='never'
```

Reinicie a instância demo para recriar o pool; confirme URL/host/database efetivos sem exibir a senha. Se o backend usa datasource personalizado ou perfis que sobrescrevem propriedades, ajuste o datasource real com o responsável. Revise também jobs de carga/migração e integrações para não apontarem para serviços de produção. Não é necessário mudar o `.env.example` global deste repositório: suas variáveis POSTGRES_* não configuram automaticamente outro aplicativo Spring.

**Login:** hashes da carga são fictícios e não garantem autenticação. Crie uma conta demo pelo fluxo de cadastro/admin do backend, com vínculo à empresa desejada; não copie credenciais reais nem enfraqueça autenticação. Para demonstrar receita, associe o usuário à empresa 1 e confirme que as compras usam produtos dessa empresa.

`127.0.0.1` só funciona para backend e Power BI Desktop na mesma máquina do banco. Se o backend estiver hospedado remotamente, ele não alcança esse banco local. Para hoje, rode backend e Power BI Desktop na máquina da demonstração, ou providencie PostgreSQL dedicado alcançável por ambos. Publicação no Power BI Service com fonte local exige gateway e configuração própria; não foi testada. A interface também precisa apontar para a API demo, e não para a API hospedada de produção.

Daniel: em Power BI Desktop, configure fonte PostgreSQL com servidor `127.0.0.1:55432`, banco `kairos_demo` e credenciais locais. Ajuste todas as consultas/dimensões da demo, não apenas uma view. Selecione DirectQuery e atualização automática da página quando disponíveis; aplique RLS e confira a empresa. Após uma compra real concluída pela API demo, confirme aumento no SQL e depois no visual. O teste SQL com ROLLBACK não serve para mostrar uma compra persistente no relatório.

Referências: [datasource Spring Boot](https://docs.spring.io/spring-boot/reference/data/sql.html), [propriedades Hikari](https://docs.spring.io/spring-boot/appendix/application-properties/index.html), [atualização automática Power BI](https://learn.microsoft.com/power-bi/create-reports/desktop-automatic-page-refresh).

## Alternativa para quem já tem uma cópia restaurada

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
