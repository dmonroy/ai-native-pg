-- Test 15: Category Embedding Cache Statistics
-- Tests the cache statistics function and GUC configuration

\set ON_ERROR_STOP on

-- Test that cache statistics function exists and returns correct structure
SELECT
    hits >= 0 AS has_hits,
    misses >= 0 AS has_misses,
    entries >= 0 AS has_entries,
    memory_mb >= 0 AS has_memory
FROM ai.classify_cache_stats();

-- Test cache starts empty (before any classification operations)
SELECT
    hits = 0 AS zero_hits,
    misses = 0 AS zero_misses,
    entries = 0 AS zero_entries,
    memory_mb = 0 AS zero_memory
FROM ai.classify_cache_stats();

-- Test GUC variable exists and has reasonable default
SHOW ai.max_cached_categories;

-- Test that GUC can be changed (session-level)
SET ai.max_cached_categories = 5000;
SHOW ai.max_cached_categories;

-- Reset to default
RESET ai.max_cached_categories;
SHOW ai.max_cached_categories;

-- Verify statistics remain consistent after GUC changes
SELECT
    hits >= 0 AS valid_hits,
    misses >= 0 AS valid_misses,
    entries >= 0 AS valid_entries,
    memory_mb >= 0 AS valid_memory
FROM ai.classify_cache_stats();

-- Note: Cache behavior (hits/misses/entries) will be tested
-- indirectly through ai.classify() functions in Section 2.2
