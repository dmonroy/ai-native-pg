-- Test 16: Classification with Array Categories
-- Tests ai.classify(text, text[]) function

\set ON_ERROR_STOP on

-- Test basic classification with clear distinctions
SELECT ai.classify(
    'Python is a programming language',
    ARRAY['technology', 'sports', 'cooking']
) = 'technology' AS tech_classification;

SELECT ai.classify(
    'The team scored three goals in the final match',
    ARRAY['technology', 'sports', 'cooking']
) = 'sports' AS sports_classification;

SELECT ai.classify(
    'Add flour and sugar to the bowl',
    ARRAY['technology', 'sports', 'cooking']
) = 'cooking' AS cooking_classification;

-- Test with more categories (use very clear technical term)
SELECT ai.classify(
    'Python programming and software development',
    ARRAY['technology', 'sports', 'cooking', 'finance', 'politics']
) = 'technology' AS tech_with_more_categories;

-- Test with similar categories (nuanced distinction)
SELECT ai.classify(
    'Machine learning models require training data',
    ARRAY['artificial intelligence', 'computer science', 'data science']
) IN ('artificial intelligence', 'data science') AS ai_or_ds;

-- Test minimum categories (2)
SELECT ai.classify(
    'The stock market crashed today',
    ARRAY['finance', 'sports']
) = 'finance' AS min_categories;

-- Test NULL text handling
SELECT ai.classify(
    NULL,
    ARRAY['technology', 'sports']
) IS NULL AS null_text;

-- Note: Error cases are tested separately as they will raise exceptions
-- These are documented in the test expectations but not executed here
-- to avoid stopping the test suite:
-- - Empty text should error: ai.classify('', ARRAY['a', 'b'])
-- - NULL categories should error: ai.classify('text', NULL::text[])
-- - Too few categories should error: ai.classify('text', ARRAY['only_one'])
-- - Empty array should error: ai.classify('text', ARRAY[]::text[])

-- Test duplicate categories (should work or warn)
SELECT ai.classify(
    'Python programming tutorial',
    ARRAY['technology', 'technology', 'sports']
) = 'technology' AS duplicate_categories;

-- Test with very long category names
SELECT ai.classify(
    'sports article',
    ARRAY['technology', 'sports and athletics and physical activities', 'cooking']
) = 'sports and athletics and physical activities' AS long_category_name;

-- Test that function returns one of the provided categories (preserving exact case)
SELECT ai.classify(
    'Software development with TypeScript, React, and Node.js frameworks',
    ARRAY['Technology', 'Sports', 'Cooking']
) IN ('Technology', 'Sports', 'Cooking') AS returns_valid_category;

-- Test cache effectiveness (second call should be faster due to cached category embeddings)
-- First set of calls
SELECT ai.classify('test 1', ARRAY['cat1', 'cat2', 'cat3']) IS NOT NULL AS call1;
SELECT ai.classify('test 2', ARRAY['cat1', 'cat2', 'cat3']) IS NOT NULL AS call2;
SELECT ai.classify('test 3', ARRAY['cat1', 'cat2', 'cat3']) IS NOT NULL AS call3;

-- Check cache has entries
SELECT entries >= 3 AS has_cached_categories FROM ai.classify_cache_stats();

-- Test with unicode categories
SELECT ai.classify(
    'Japanese technology',
    ARRAY['技術', 'スポーツ', '料理']
) = '技術' AS unicode_categories;

-- Test realistic scenario: content categorization
SELECT ai.classify(
    'Breaking: New AI model achieves state-of-the-art results on ImageNet',
    ARRAY['artificial intelligence', 'sports', 'politics', 'entertainment', 'science']
) IN ('artificial intelligence', 'science') AS realistic_news_categorization;
