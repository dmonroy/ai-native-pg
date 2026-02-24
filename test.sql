-- Test queries for AI extension PoC

\echo '=== AI Extension Tests ==='
\echo ''

\echo '1. Check extension version'
SELECT ai.version();
\echo ''

\echo '2. Health check'
SELECT ai.health_check();
\echo ''

\echo '3. Test ai.embed() - will fail with "not yet implemented" (expected)'
\echo '   This proves the function exists and is callable'
SELECT ai.embed('Hello world');
\echo ''

\echo '4. Test with NULL input (should return NULL)'
SELECT ai.embed(NULL);
\echo ''

\echo '5. Test with empty string (should error)'
SELECT ai.embed('');
\echo ''

\echo '6. Test with long input (should validate length)'
SELECT ai.embed(repeat('x', 10000));
\echo ''

\echo '=== Generated Column Test (will fail until inference implemented) ==='
\echo ''

\echo 'Creating table with generated embedding column...'
DROP TABLE IF EXISTS test_docs;
CREATE TABLE test_docs (
  id SERIAL PRIMARY KEY,
  content TEXT,
  embedding vector(384) GENERATED ALWAYS AS (ai.embed(content)) STORED
);

\echo 'Inserting test data...'
INSERT INTO test_docs (content) VALUES
  ('PostgreSQL is awesome'),
  ('AI embeddings are cool'),
  ('Vector databases rock');

\echo 'Querying with embeddings...'
SELECT id, content FROM test_docs;
\echo ''

\echo 'Test complete!'
