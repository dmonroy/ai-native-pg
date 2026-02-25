-- Test 17: Classification with Threshold
-- Tests ai.classify(text, text[], threshold) function

\set ON_ERROR_STOP on

-- Test basic threshold classification - clear match above threshold
SELECT ai.classify(
    'Python programming and software development',
    ARRAY['technology', 'sports', 'cooking'],
    0.5
) = 'technology' AS clear_match_above_threshold;

-- Test threshold rejection - ambiguous content with high threshold
SELECT ai.classify(
    'The event was interesting',
    ARRAY['technology', 'sports', 'cooking'],
    0.9
) IS NULL AS ambiguous_rejected_high_threshold;

-- Test low threshold accepts anything
SELECT ai.classify(
    'Random text here',
    ARRAY['technology', 'sports', 'cooking'],
    0.0
) IS NOT NULL AS low_threshold_accepts;

-- Test threshold 1.0 (perfect match only) - very strict
SELECT ai.classify(
    'Some content',
    ARRAY['technology', 'sports', 'cooking'],
    1.0
) IS NULL AS perfect_match_only;

-- Test threshold values: 0.3, 0.5, 0.7
SELECT ai.classify(
    'Football match and soccer game',
    ARRAY['technology', 'sports', 'cooking'],
    0.3
) = 'sports' AS threshold_30;

SELECT ai.classify(
    'Football match and soccer game',
    ARRAY['technology', 'sports', 'cooking'],
    0.5
) = 'sports' AS threshold_50;

SELECT ai.classify(
    'Football match and soccer game',
    ARRAY['technology', 'sports', 'cooking'],
    0.7
) IN ('sports', NULL::text) AS threshold_70_maybe_null;

-- Test NULL content handling (should return NULL)
SELECT ai.classify(
    NULL,
    ARRAY['technology', 'sports'],
    0.5
) IS NULL AS null_content;

-- Test that cache still works with threshold variant
-- Using low threshold to ensure results are returned
SELECT ai.classify('technology article', ARRAY['tech', 'sports'], 0.1) IS NOT NULL AS call1;
SELECT ai.classify('sports news', ARRAY['tech', 'sports'], 0.1) IS NOT NULL AS call2;
SELECT entries >= 2 AS cache_working FROM ai.classify_cache_stats();

-- Test threshold boundary values
SELECT ai.classify(
    'Programming code',
    ARRAY['technology', 'sports'],
    0.0
) IS NOT NULL AS threshold_min;

-- Test realistic scenario: content moderation with threshold
SELECT ai.classify(
    'This is a normal product review about a laptop',
    ARRAY['spam', 'appropriate', 'offensive'],
    0.6
) = 'appropriate' AS content_moderation;

-- Test with unicode categories and threshold
SELECT ai.classify(
    'Technology and computers',
    ARRAY['技術', 'スポーツ', '料理'],
    0.4
) = '技術' AS unicode_with_threshold;
