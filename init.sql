-- Initialize AI extension on database creation
-- This runs automatically when container starts

\echo 'Installing pgvector extension...'
CREATE EXTENSION IF NOT EXISTS vector;

\echo 'Installing ai extension...'
CREATE EXTENSION IF NOT EXISTS ai;

\echo 'Running health check...'
SELECT ai.health_check();

\echo 'AI extension installed successfully!'
\echo 'Try: SELECT ai.health_check();'
