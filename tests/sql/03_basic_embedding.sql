-- Test 03: Basic Embedding Functionality

\set ON_ERROR_STOP on

-- Returns non-NULL for valid input
SELECT ai.embed('Hello world') IS NOT NULL AS returns_non_null;

-- Returns vector type
SELECT pg_typeof(ai.embed('test')) = 'vector'::regtype AS returns_vector_type;

-- Returns 384 dimensions
SELECT vector_dims(ai.embed('Hello world')) = 384 AS correct_dimensions;

-- Same input produces same output (deterministic)
SELECT ai.embed('test') = ai.embed('test') AS is_deterministic;

-- Different inputs produce different outputs
SELECT ai.embed('cat') <> ai.embed('dog') AS different_inputs_differ;

-- Can embed single word
SELECT vector_dims(ai.embed('cat')) = 384 AS single_word_works;

-- Can embed sentence
SELECT vector_dims(ai.embed('The quick brown fox')) = 384 AS sentence_works;

-- Can embed paragraph
SELECT vector_dims(ai.embed('This is a longer text. It has multiple sentences. Testing paragraph embedding.')) = 384 AS paragraph_works;
