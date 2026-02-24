-- Test 08: IMMUTABLE Function Property

\set ON_ERROR_STOP on

-- embed() is marked IMMUTABLE
SELECT provolatile = 'i' AS embed_is_immutable
FROM pg_proc
WHERE proname = 'embed'
LIMIT 1;

-- Can be used in generated columns
CREATE TEMP TABLE test_generated (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(384) GENERATED ALWAYS AS (ai.embed(content)) STORED
);

-- Insert test data
INSERT INTO test_generated (content) VALUES
    ('PostgreSQL database'),
    ('Machine learning'),
    ('Vector search');

-- Verify embeddings were generated
SELECT COUNT(*) = 3 AS all_embeddings_generated
FROM test_generated
WHERE embedding IS NOT NULL;

-- Verify all have correct dimensions
SELECT COUNT(*) = 3 AS all_correct_dimensions
FROM test_generated
WHERE vector_dims(embedding) = 384;

-- Can use in indexes (IMMUTABLE required)
CREATE INDEX test_idx ON test_generated USING ivfflat (embedding vector_cosine_ops);

-- Index was created
SELECT COUNT(*) = 1 AS index_created
FROM pg_indexes
WHERE tablename = 'test_generated' AND indexname = 'test_idx';
