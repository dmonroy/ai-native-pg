-- Test 15: Category Embedding Cache
-- Tests the category cache infrastructure that enables fast classification

\set ON_ERROR_STOP on

-- Test that cache statistics function exists
SELECT
    hits >= 0 AS has_hits,
    misses >= 0 AS has_misses,
    entries >= 0 AS has_entries,
    memory_mb >= 0 AS has_memory
FROM ai.classify_cache_stats();

-- Test cache is initially empty
SELECT
    hits = 0 AS zero_hits,
    misses = 0 AS zero_misses,
    entries = 0 AS zero_entries
FROM ai.classify_cache_stats();

-- Test internal get_category_embedding function
-- Note: This will be exposed for testing via ai.test_get_category_embedding()
-- First call should be a cache miss
SELECT vector_dims(ai.test_get_category_embedding('technology')) = 768 AS correct_dims;

-- Check that cache now has 1 entry and 1 miss
SELECT
    misses = 1 AS one_miss,
    entries = 1 AS one_entry,
    hits = 0 AS still_zero_hits
FROM ai.classify_cache_stats();

-- Second call with same category should be a cache hit
SELECT vector_dims(ai.test_get_category_embedding('technology')) = 768 AS still_correct;

-- Check that we now have 1 hit
SELECT
    hits = 1 AS one_hit,
    misses = 1 AS still_one_miss,
    entries = 1 AS still_one_entry
FROM ai.classify_cache_stats();

-- Test with multiple different categories
SELECT vector_dims(ai.test_get_category_embedding('science')) = 768 AS cat2;
SELECT vector_dims(ai.test_get_category_embedding('business')) = 768 AS cat3;
SELECT vector_dims(ai.test_get_category_embedding('sports')) = 768 AS cat4;

-- Check cache now has 4 entries and 4 misses (plus previous 1 hit)
SELECT
    entries = 4 AS four_entries,
    misses = 4 AS four_misses,
    hits = 1 AS one_hit
FROM ai.classify_cache_stats();

-- Test repeated access creates hits
SELECT vector_dims(ai.test_get_category_embedding('science')) = 768 AS hit1;
SELECT vector_dims(ai.test_get_category_embedding('business')) = 768 AS hit2;

-- Check hit count increased
SELECT
    entries = 4 AS still_four,
    misses = 4 AS still_four_misses,
    hits = 3 AS three_hits
FROM ai.classify_cache_stats();

-- Test memory usage is reasonable (~2KB per category = ~0.008 MB for 4 entries)
SELECT memory_mb < 0.1 AS reasonable_memory
FROM ai.classify_cache_stats();

-- Test cache with special characters and unicode
SELECT vector_dims(ai.test_get_category_embedding('日本語')) = 768 AS unicode_works;
SELECT vector_dims(ai.test_get_category_embedding('hello world!')) = 768 AS spaces_work;

-- Verify cache statistics are consistent
SELECT
    entries >= 4 AS at_least_four,
    (hits + misses) > 0 AS has_activity,
    hits <= misses + entries AS sane_values
FROM ai.classify_cache_stats();
