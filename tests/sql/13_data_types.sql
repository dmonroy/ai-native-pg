-- Test 13: Data Type Compatibility

\set ON_ERROR_STOP on

-- Works with TEXT type
SELECT vector_dims(ai.embed('text'::TEXT)) = 768 AS text_type_works;

-- Works with VARCHAR
SELECT vector_dims(ai.embed('varchar'::VARCHAR(100))) = 768 AS varchar_works;

-- Works with concatenation
SELECT vector_dims(ai.embed('Hello' || ' ' || 'World')) = 768 AS concat_works;

-- Works with string literals
SELECT vector_dims(ai.embed($$Dollar quoted string$$)) = 768 AS dollar_quote_works;

-- Works with escaped strings
SELECT vector_dims(ai.embed(E'Escaped\nString')) = 768 AS escaped_string_works;

-- Works in subquery
SELECT COUNT(*) = 1 AS subquery_works
FROM (SELECT ai.embed('subquery') AS e) sq
WHERE vector_dims(e) = 768;

-- Works in CTE
WITH cte AS (
    SELECT ai.embed('cte test') AS embedding
)
SELECT vector_dims(embedding) = 768 AS cte_works
FROM cte;
