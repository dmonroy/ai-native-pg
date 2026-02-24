-- Test 12: Concurrent Operations

\set ON_ERROR_STOP on

-- Multiple simultaneous embeds work
WITH concurrent AS (
    SELECT
        ai.embed('text1') as e1,
        ai.embed('text2') as e2,
        ai.embed('text3') as e3,
        ai.embed('text4') as e4,
        ai.embed('text5') as e5
)
SELECT
    (e1 IS NOT NULL) AND
    (e2 IS NOT NULL) AND
    (e3 IS NOT NULL) AND
    (e4 IS NOT NULL) AND
    (e5 IS NOT NULL)
    AS concurrent_embeds_work
FROM concurrent;

-- Batch insert works
CREATE TEMP TABLE batch_test (
    id SERIAL PRIMARY KEY,
    text TEXT,
    embedding vector(384)
);

INSERT INTO batch_test (text, embedding)
SELECT
    'Document ' || i::text,
    ai.embed('Document ' || i::text)
FROM generate_series(1, 20) i;

SELECT COUNT(*) = 20 AS batch_insert_works
FROM batch_test WHERE embedding IS NOT NULL;

-- Multiple table operations work
CREATE TEMP TABLE table1 (embedding vector(384));
CREATE TEMP TABLE table2 (embedding vector(384));

INSERT INTO table1 SELECT ai.embed('table1 data');
INSERT INTO table2 SELECT ai.embed('table2 data');

SELECT
    (SELECT COUNT(*) FROM table1) = 1 AND
    (SELECT COUNT(*) FROM table2) = 1
    AS multiple_tables_work;
