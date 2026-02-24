-- Test 14: Real-World Scenario

\set ON_ERROR_STOP on

-- Create a realistic documents table
CREATE TEMP TABLE articles (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    embedding vector(384)
);

-- Insert sample articles
INSERT INTO articles (title, content, category) VALUES
    ('Introduction to PostgreSQL', 'PostgreSQL is a powerful open-source relational database', 'Database'),
    ('Machine Learning Basics', 'Machine learning is a subset of artificial intelligence', 'AI'),
    ('Vector Databases Explained', 'Vector databases enable semantic search capabilities', 'Database'),
    ('Cooking Italian Pasta', 'Traditional Italian pasta recipes and techniques', 'Food'),
    ('Travel Tips for Europe', 'Essential travel advice for European destinations', 'Travel');

-- Generate embeddings for all articles
UPDATE articles SET embedding = ai.embed(title || '. ' || content);

-- All embeddings generated
SELECT COUNT(*) = 5 AS all_embeddings_generated
FROM articles WHERE embedding IS NOT NULL;

-- Semantic search returns results
SELECT COUNT(*) >= 1 AS semantic_search_works
FROM (
    SELECT * FROM articles
    ORDER BY embedding <=> ai.embed('database systems')
    LIMIT 2
) results;

-- Category filtering with search
SELECT COUNT(*) = 1 AS filtered_search_works
FROM (
    SELECT * FROM articles
    WHERE category = 'AI'
    ORDER BY embedding <=> ai.embed('artificial intelligence')
    LIMIT 1
) results;

-- Find similar articles
SELECT COUNT(*) >= 1 AS similar_articles_found
FROM (
    SELECT * FROM articles
    WHERE title != 'Introduction to PostgreSQL'
    ORDER BY embedding <=> ai.embed('PostgreSQL database')
    LIMIT 3
) AS similar_results;

-- Aggregate with embeddings
SELECT COUNT(DISTINCT category) >= 3 AS aggregation_works
FROM articles
WHERE embedding IS NOT NULL;
