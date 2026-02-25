-- Test 19: Combined Threshold + Top-K Classification
-- Tests ai.classify(text, text[], threshold, top_k) function

\set ON_ERROR_STOP on

-- Test basic combined: threshold 0.5, top-3
SELECT array_length(ai.classify(
    content => 'Python programming and software development',
    categories => ARRAY['technology', 'sports', 'cooking', 'finance', 'politics'],
    threshold => 0.5,
    top_k => 3
), 1) <= 3 AS returns_at_most_three;

-- Test high threshold may return fewer than top_k
SELECT array_length(ai.classify(
    content => 'Generic ambiguous content here',
    categories => ARRAY['category1', 'category2', 'category3'],
    threshold => 0.9,
    top_k => 3
), 1) <= 3 AS fewer_than_topk_ok;

-- Test low threshold returns full top_k
SELECT array_length(ai.classify(
    content => 'Technology and computers',
    categories => ARRAY['tech', 'sports', 'cooking'],
    threshold => 0.1,
    top_k => 2
), 1) = 2 AS low_threshold_full_topk;

-- Test all below threshold returns empty array
SELECT ai.classify(
    content => 'Random unrelated content xyz',
    categories => ARRAY['very_specific_cat1', 'very_specific_cat2'],
    threshold => 0.95,
    top_k => 5
) = ARRAY[]::text[] AS all_below_threshold;

-- Test NULL content returns NULL
SELECT ai.classify(
    content => NULL,
    categories => ARRAY['tech', 'sports'],
    threshold => 0.5,
    top_k => 3
) IS NULL AS null_content;

-- Test realistic: content moderation with multi-label
SELECT ai.classify(
    content => 'This product is good quality laptop computer',
    categories => ARRAY['spam', 'appropriate', 'offensive', 'promotional'],
    threshold => 0.4,
    top_k => 2
) @> ARRAY['appropriate'] AS moderation_multilabel;

-- Test cache works with combined variant
SELECT array_length(ai.classify(content => 'tech', categories => ARRAY['a', 'b'], threshold => 0.1, top_k => 2), 1) >= 0 AS call1;
SELECT array_length(ai.classify(content => 'sports', categories => ARRAY['a', 'b'], threshold => 0.1, top_k => 2), 1) >= 0 AS call2;
SELECT entries >= 2 AS cache_working FROM ai.classify_cache_stats();

-- Test unicode with combined
SELECT ai.classify(
    content => 'Technology news',
    categories => ARRAY['技術', 'スポーツ', '料理'],
    threshold => 0.3,
    top_k => 2
) <@ ARRAY['技術', 'スポーツ', '料理'] AS unicode_combined;
