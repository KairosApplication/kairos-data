# Kairos Database

Repositório responsável pelos scripts de banco de dados do projeto Kairos.

O projeto utiliza PostgreSQL para os dados principais do sistema e MongoDB Atlas para a parte de inteligência artificial, histórico de conversas e memória da IA.

## Tecnologias

- PostgreSQL
- MongoDB Atlas
- Redis (in development)
- Neo4j (backlog)

## Estrutura do repositório

```text
postgres/
Scripts do banco relacional principal do Kairos.

mongodb-atlas/
Scripts e documentação das collections do MongoDB Atlas.

docs/
Documentação do banco, regras de negócio e dicionário de dados.

<!-- docs-bot:start -->
## Documentação

- [Revisão final de Modelagem — Kairos](docs/FINAL_MODELAGEM_REVIEW.md)
- [Kairos | Entregas restantes de Modelagem e Engenharia de Dados](docs/README.md)
- [Kairos — Procedimento e evidência de backup e recuperação](docs/backup_recuperacao.md)
- [Demonstração de 02/11/2026](docs/demo_datas.md)
- [Testes executados em 02/11/2026](docs/demo_test_results.md)
- [Kairos | Contrato de integração DAU com backend](docs/integracao_dau_backend.md)
- [Normalização e cardinalidades — análise final, 02/11/2026](docs/normalizacao_cardinalidades.md)
- [Performance final — PostgreSQL, 02/11/2026](docs/performance_final.md)
<!-- docs-bot:end -->
