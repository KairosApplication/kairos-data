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