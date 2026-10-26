# Kairos | Entregas restantes de Modelagem e Engenharia de Dados

Este pacote contém **scripts incrementais** para o schema PostgreSQL do Kairos. Foi elaborado a partir dos nomes e campos dos scripts de dataload e rotinas compartilhados. **Não substitui o schema existente nem executa a carga de dados novamente.**

## Ordem de execução no pgAdmin / DBeaver

1. Confirme que já executou o **schema atual**, com Employees.position `MANAGER/STOCKER/CASHIER`.
2. Confirme que a carga do milhão de registros terminou e as tabelas existem.
3. Execute `04_bi_views.sql` (alinhar antes com **Dani**, responsável pelo BI).
4. Execute `05_performance_indexes.sql` e **salve os planos ANTES e DEPOIS**; os ganhos não são garantidos.
5. Execute `07_dau.sql` (cria infraestrutura de DAU, não coleta acessos automaticamente até a integração com o backend).
6. Execute `06_data_catalog.sql` **depois do DAU** para documentar também a tabela `User_Accesses`.
7. Execute `08_advanced_queries.sql` (hierarquia recursiva de setores, corredores e prateleiras).
8. Execute `09_model_validation.sql` (checks de consistência, cardinalidades técnicas e revisão).
9. Siga `backup_restore.md` para testar backup e recuperação **em banco separado**.

Cada `.sql` pode ser aberto, selecionado inteiro (`Ctrl+A`) e executado. Nenhum destes arquivos contém TRUNCATE, DELETE de dados de negócio, DROP TABLE ou DROP SCHEMA. **O catálogo faz um DELETE apenas de seus próprios metadados desatualizados**, após cruzar colunas atuais do schema. Há SELECTs finais de teste dentro dos scripts.

## Arquivos

| Arquivo | Requisito | Entrega |
|---|---|---|
| `04_bi_views.sql` | Data Mart, CTE, Window Functions | Views de dimensões, fatos, ranking e acumulados. Revisar com Dani. |
| `05_performance_indexes.sql` | EXPLAIN ANALYZE, índices | Planos de execução antes/depois e 5 índices. |
| `06_data_catalog.sql` | Governança | Data_Catalog com colunas, constraints, classificação de acesso. |
| `07_dau.sql` | Monitoramento | User_Accesses, função de registro, views de DAU. |
| `08_advanced_queries.sql` | Estruturas avançadas | View de hierarquia usando WITH RECURSIVE. |
| `09_model_validation.sql` | Normalização e integridade | Diagnóstico de isolamento multiempresa e FKs. |
| `backup_restore.md` | Backup e recuperação | Procedimento de backup e restauração em base separada. |
| `normalizacao_cardinalidades.md` | 3FN e cardinalidades | Revisão preliminar e documentação das relações. |
| `integracao_dau_backend.md` | Automação DAU | Contrato e critérios de teste para integração pelo backend. |

## Pendências que ainda exigem ação humana

- **Davi/backend:** chamar `SELECT register_user_access(user_id, company_id)` com valores verificados pela autenticação e autorização do sistema. Sem isso o DAU permanece vazio. Evitar registrar robôs e sondas como usuários ativos.
- **Dani/BI:** alinhar as views entregues, permissão/isolamento por empresa e o conector JDBC/nativo escolhido. As views não implementam autorização de consultas por si só.
- **Equipe:** comparar planos reais no `EXPLAIN ANALYZE`, registrar resultados, revisar regras de negócio do catálogo, executar restore em banco vazio, confirmar 3FN e identificar inconsistências multiempresa.
- **Equipe:** adicionar migrações/método de deploy do novo esquema para outros ambientes. Evitar execução automática em produção sem revisão.

## Observações técnicas

- As tabelas/tipos usados aqui correspondem ao dataload que foi compartilhado: Companies, Users, Employees, Products, Restockings, Purchases e demais relacionamentos.
- O Data Mart é uma **modelagem dimensional lógica baseada em views**, não um banco analítico materializado; alinhar isso com a interpretação do professor.
- Os arquivos **não foram executados em uma instância PostgreSQL do seu projeto**, e não foi possível medir desempenho real ou verificar credenciais/permissões do ambiente.
- DAU usa data de São Paulo: `America/Sao_Paulo`. Deve ser adaptado se houver empresas em outros fusos.
- Atenção à normalização: `Inventories.company_id` e `Inventories.sector_id` potencialmente criam dependência transitiva se todo estoque sempre tiver setor. A revisão de 3FN não está encerrada apenas por rodar esses scripts.
- O modelo multitenant atual tem FKs isoladas que não garantem sozinhas a correspondência da empresa entre entidades; consulte o relatório de `09_model_validation.sql`.
- O catálogo marca níveis de acesso, mas **não aplica GRANT/REVOKE ou RLS**. Segurança depende de permissões reais e backend.
- Nunca commitar `.env`, senhas ou arquivos `.dump`.
