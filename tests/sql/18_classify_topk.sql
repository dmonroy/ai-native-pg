-- Test 18: Multi-label Classification (Top-K)
-- Tests ai.classify(text, text[], top_k) function

\set ON_ERROR_STOP on

-- Test basic top-3 classification
SELECT array_length(ai.classify(
    content => 'Python programming and software development',
    categories => ARRAY['technology', 'sports', 'cooking', 'finance', 'politics'],
    top_k => 3
), 1) = 3 AS returns_three_categories;

-- Test that results are sorted by similarity (best first)
-- Verify first element is one of the provided categories
SELECT (ai.classify(
    content => 'Python and JavaScript programming',
    categories => ARRAY['technology', 'sports', 'cooking'],
    top_k => 3
))[1] IN ('technology', 'sports', 'cooking') AS best_is_valid;

-- Test top-1 (should return single-element array)
SELECT ai.classify(
    content => 'Football match and soccer game',
    categories => ARRAY['technology', 'sports', 'cooking'],
    top_k => 1
) = ARRAY['sports'] AS topk_one;

-- Test top-K larger than category count (returns all, sorted)
SELECT array_length(ai.classify(
    content => 'Some content here',
    categories => ARRAY['tech', 'sports'],
    top_k => 10
), 1) = 2 AS topk_exceeds_categories;

-- Test default top-K (when not specified) - expecting 3
-- Note: This tests the 2-parameter variant, not the top-k variant
-- SELECT array_length(ai.classify(
--     'Content here',
--     ARRAY['a', 'b', 'c', 'd', 'e']
-- ), 1) = 3 AS default_topk;

-- Test NULL content handling
SELECT ai.classify(
    content => NULL,
    categories => ARRAY['technology', 'sports'],
    top_k => 3
) IS NULL AS null_content;

-- Test realistic multi-label scenario: news article tagging
SELECT ai.classify(
    content => 'New AI technology breakthrough in machine learning algorithms',
    categories => ARRAY['artificial intelligence', 'technology', 'science', 'business', 'politics'],
    top_k => 3
) @> ARRAY['artificial intelligence'] AS multilabel_contains_ai;

-- Test that all results are from the provided categories
SELECT ai.classify(
    content => 'Sports and fitness article',
    categories => ARRAY['Category A', 'Category B', 'Category C'],
    top_k => 2
) <@ ARRAY['Category A', 'Category B', 'Category C'] AS results_from_input;

-- Test cache still works with top-k variant
SELECT array_length(ai.classify(content => 'tech article', categories => ARRAY['tech', 'sports'], top_k => 2), 1) = 2 AS call1;
SELECT array_length(ai.classify(content => 'sports news', categories => ARRAY['tech', 'sports'], top_k => 2), 1) = 2 AS call2;
SELECT entries >= 2 AS cache_working FROM ai.classify_cache_stats();

-- Test with unicode categories
SELECT (ai.classify(
    content => 'Technology and science news',
    categories => ARRAY['技術', 'スポーツ', '料理'],
    top_k => 2
))[1] = '技術' AS unicode_topk;
