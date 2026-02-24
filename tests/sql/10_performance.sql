-- Test 10: Performance and Determinism

\set ON_ERROR_STOP on

-- Can generate 10 embeddings quickly
SELECT COUNT(*) = 10 AS batch_10_works
FROM (
    SELECT ai.embed('text ' || i::text)
    FROM generate_series(1, 10) i
) AS batch;

-- Can generate 50 embeddings
SELECT COUNT(*) = 50 AS batch_50_works
FROM (
    SELECT ai.embed('document ' || i::text)
    FROM generate_series(1, 50) i
) AS batch;

-- Deterministic: same input always produces same output
WITH tests AS (
    SELECT
        ai.embed('deterministic test') as v1,
        ai.embed('deterministic test') as v2,
        ai.embed('deterministic test') as v3
)
SELECT (v1 = v2) AND (v2 = v3) AS is_deterministic
FROM tests;

-- Repeated calls produce identical results
SELECT
    (ai.embed('repeat') <=> ai.embed('repeat')) < 0.0001
    AS repeated_calls_identical;

-- Function is stable across sessions (IMMUTABLE guarantees this)
SELECT provolatile = 'i' AS function_is_stable
FROM pg_proc WHERE proname = 'embed' LIMIT 1;
