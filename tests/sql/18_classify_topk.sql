-- Test 18: Multi-label Classification (Top-K)
-- Tests ai.classify(text, text[], top_k) function

\set ON_ERROR_STOP on

-- Test basic top-3 classification
SELECT array_length(ai.classify(
    'Python programming and software development',
    ARRAY['technology', 'sports', 'cooking', 'finance', 'politics'],
    3
), 1) = 3 AS returns_three_categories;

-- Test that results are sorted by similarity (best first)
-- Verify first element is one of the provided categories
SELECT (ai.classify(
    'Python and JavaScript programming',
    ARRAY['technology', 'sports', 'cooking'],
    3
))[1] IN ('technology', 'sports', 'cooking') AS best_is_valid;

-- Test top-1 (should return single-element array)
SELECT ai.classify(
    'Football match and soccer game',
    ARRAY['technology', 'sports', 'cooking'],
    1
) = ARRAY['sports'] AS topk_one;

-- Test top-K larger than category count (returns all, sorted)
SELECT array_length(ai.classify(
    'Some content here',
    ARRAY['tech', 'sports'],
    10
), 1) = 2 AS topk_exceeds_categories;

-- Test default top-K (when not specified) - expecting 3
-- Note: This tests the 2-parameter variant, not the top-k variant
-- SELECT array_length(ai.classify(
--     'Content here',
--     ARRAY['a', 'b', 'c', 'd', 'e']
-- ), 1) = 3 AS default_topk;

-- Test NULL content handling
SELECT ai.classify(
    NULL,
    ARRAY['technology', 'sports'],
    3
) IS NULL AS null_content;

-- Test realistic multi-label scenario: news article tagging
SELECT ai.classify(
    'New AI technology breakthrough in machine learning algorithms',
    ARRAY['artificial intelligence', 'technology', 'science', 'business', 'politics'],
    3
) @> ARRAY['artificial intelligence'] AS multilabel_contains_ai;

-- Test that all results are from the provided categories
SELECT ai.classify(
    'Sports and fitness article',
    ARRAY['Category A', 'Category B', 'Category C'],
    2
) <@ ARRAY['Category A', 'Category B', 'Category C'] AS results_from_input;

-- Test cache still works with top-k variant
SELECT array_length(ai.classify('tech article', ARRAY['tech', 'sports'], 2), 1) = 2 AS call1;
SELECT array_length(ai.classify('sports news', ARRAY['tech', 'sports'], 2), 1) = 2 AS call2;
SELECT entries >= 2 AS cache_working FROM ai.classify_cache_stats();

-- Test with unicode categories
SELECT (ai.classify(
    'Technology and science news',
    ARRAY['技術', 'スポーツ', '料理'],
    2
))[1] = '技術' AS unicode_topk;
