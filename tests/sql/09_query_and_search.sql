-- Test 09: Query and Search Operations

\set ON_ERROR_STOP on

-- Create test table with documents
CREATE TEMP TABLE documents (
    id SERIAL PRIMARY KEY,
    title TEXT,
    embedding vector(768)
);

-- Insert test documents
INSERT INTO documents (title, embedding) VALUES
    ('PostgreSQL database system', ai.embed('PostgreSQL database system')),
    ('Machine learning algorithms', ai.embed('Machine learning algorithms')),
    ('Vector similarity search', ai.embed('Vector similarity search')),
    ('Cooking recipes for pasta', ai.embed('Cooking recipes for pasta')),
    ('Travel guide to Japan', ai.embed('Travel guide to Japan'));

-- All embeddings were inserted
SELECT COUNT(*) = 5 AS all_inserted
FROM documents WHERE embedding IS NOT NULL;

-- Can query by similarity (just check it returns results)
SELECT COUNT(*) = 1 AS similarity_query_works
FROM (
    SELECT * FROM documents
    ORDER BY embedding <=> ai.embed('database')
    LIMIT 1
) AS nearest;

-- Can find K nearest neighbors
SELECT COUNT(*) = 3 AS knn_works
FROM (
    SELECT * FROM documents
    ORDER BY embedding <=> ai.embed('technology')
    LIMIT 3
) AS top_3;

-- Can filter and search
SELECT COUNT(*) >= 1 AS filtered_search_works
FROM (
    SELECT * FROM documents
    WHERE title LIKE '%data%'
    ORDER BY embedding <=> ai.embed('SQL')
    LIMIT 1
) AS filtered;
