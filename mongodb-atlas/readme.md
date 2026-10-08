# MongoDB Atlas - Kairos AI

O MongoDB do Kairos está hospedado no MongoDB Atlas.

Esta pasta contém apenas os scripts usados para documentar e recriar as collections, indexes e dados de teste da parte de inteligência artificial do projeto.

## Database

kairos_ai

## Ordem de execução

1. 01_create_collections.mongodb.js
2. 02_create_indexes.mongodb.js
3. 03_seed_dev.mongodb.js

## Collections

- conversations
- user_memory
- ai_executions
- agent_traces
- rag_documents
- rag_chunks
- judge_evaluations
- guardrail_events
- feedback

## Observação

Não colocar a connection string real do MongoDB Atlas no GitHub.

Exemplo do que NÃO deve subir:

mongodb+srv://usuario:senha@cluster...

A connection string real deve ficar em arquivo .env local.