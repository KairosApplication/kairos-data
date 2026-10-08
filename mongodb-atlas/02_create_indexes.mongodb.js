use('kairos_ai');

db.createCollection('conversations');
db.createCollection('user_memory');
db.createCollection('ai_executions');
db.createCollection('agent_traces');
db.createCollection('rag_documents');
db.createCollection('rag_chunks');
db.createCollection('judge_evaluations');
db.createCollection('guardrail_events');
db.createCollection('feedback');