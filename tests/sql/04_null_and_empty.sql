-- Test 04: NULL and Empty String Handling

\set ON_ERROR_STOP on

-- NULL input returns NULL
SELECT ai.embed(NULL) IS NULL AS null_returns_null;

-- Note: Empty string test is in 05_edge_cases.sql
-- (requires special error handling)
