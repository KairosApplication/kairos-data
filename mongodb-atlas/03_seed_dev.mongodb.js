use('kairos_ai');

db.conversations.createIndex({ user_id: 1 });

db.user_memory.createIndex(
    { user_id: 1 },
    { unique: true }
);

db.ai_executions.createIndex({ conversation_id: 1 });
db.ai_executions.createIndex({ user_id: 1 });

db.agent_traces.createIndex({ execution_id: 1 });

db.rag_chunks.createIndex({ document_id: 1 });

db.judge_evaluations.createIndex({ execution_id: 1 });

db.guardrail_events.createIndex({ execution_id: 1 });

db.feedback.createIndex({ execution_id: 1 });