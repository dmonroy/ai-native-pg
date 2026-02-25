-- Test 19: Combined Threshold + Top-K Classification
-- Tests ai.classify(text, text[], threshold, top_k) function

\set ON_ERROR_STOP on

-- Test basic combined: threshold 0.5, top-3
SELECT array_length(ai.classify(
    'Python programming and software development',
    ARRAY['technology', 'sports', 'cooking', 'finance', 'politics'],
    0.5,
    3
), 1) <= 3 AS returns_at_most_three;

-- Test high threshold may return fewer than top_k
SELECT array_length(ai.classify(
    'Generic ambiguous content here',
    ARRAY['category1', 'category2', 'category3'],
    0.9,
    3
), 1) <= 3 AS fewer_than_topk_ok;

-- Test low threshold returns full top_k
SELECT array_length(ai.classify(
    'Technology and computers',
    ARRAY['tech', 'sports', 'cooking'],
    0.1,
    2
), 1) = 2 AS low_threshold_full_topk;

-- Test all below threshold returns empty array
SELECT ai.classify(
    'Random unrelated content xyz',
    ARRAY['very_specific_cat1', 'very_specific_cat2'],
    0.95,
    5
) = ARRAY[]::text[] AS all_below_threshold;

-- Test NULL content returns NULL
SELECT ai.classify(
    NULL,
    ARRAY['tech', 'sports'],
    0.5,
    3
) IS NULL AS null_content;

-- Test realistic: content moderation with multi-label
SELECT ai.classify(
    'This product is good quality laptop computer',
    ARRAY['spam', 'appropriate', 'offensive', 'promotional'],
    0.4,
    2
) @> ARRAY['appropriate'] AS moderation_multilabel;

-- Test cache works with combined variant
SELECT array_length(ai.classify('tech', ARRAY['a', 'b'], 0.1, 2), 1) >= 0 AS call1;
SELECT array_length(ai.classify('sports', ARRAY['a', 'b'], 0.1, 2), 1) >= 0 AS call2;
SELECT entries >= 2 AS cache_working FROM ai.classify_cache_stats();

-- Test unicode with combined
SELECT ai.classify(
    'Technology news',
    ARRAY['技術', 'スポーツ', '料理'],
    0.3,
    2
) <@ ARRAY['技術', 'スポーツ', '料理'] AS unicode_combined;
