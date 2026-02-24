-- Test: Basic AI Extension Functionality

\set ON_ERROR_STOP on

-- Extension is loaded (fails if not found)
SELECT extname FROM pg_extension WHERE extname = 'ai';

-- Functions exist (fails if not found)
SELECT proname FROM pg_proc WHERE proname = 'embed';
SELECT proname FROM pg_proc WHERE proname = 'health_check';

-- Health check returns text
SELECT ai.health_check() LIKE '%ONNX%' AS health_check_ok;

-- Embed returns 768-dim vector
SELECT vector_dims(ai.embed('Hello world')) = 768 AS correct_dimensions;

-- NULL input returns NULL
SELECT ai.embed(NULL) IS NULL AS null_handling_ok;

-- Semantic similarity (cat closer to dog than database)
SELECT
    (ai.embed('cat') <=> ai.embed('dog')) <
    (ai.embed('cat') <=> ai.embed('database'))
    AS semantic_similarity_ok;
