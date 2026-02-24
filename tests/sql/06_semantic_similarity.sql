-- Test 06: Semantic Similarity

\set ON_ERROR_STOP on

-- Cat closer to dog than to database
SELECT (ai.embed('cat') <=> ai.embed('dog')) <
       (ai.embed('cat') <=> ai.embed('database'))
       AS cat_dog_similarity;

-- Hello closer to hi than to unrelated word
SELECT (ai.embed('hello') <=> ai.embed('hi')) <
       (ai.embed('hello') <=> ai.embed('xyzabc'))
       AS greeting_similarity;

-- King closer to queen than to computer
SELECT (ai.embed('king') <=> ai.embed('queen')) <
       (ai.embed('king') <=> ai.embed('computer'))
       AS royalty_similarity;

-- Note: nomic-embed-text-v1.5 has different emotion word semantics than bge-small
-- Testing with different example: good/great vs bad
SELECT (ai.embed('good') <=> ai.embed('great')) <
       (ai.embed('good') <=> ai.embed('bad'))
       AS emotion_similarity;

-- Car closer to vehicle than to tree
SELECT (ai.embed('car') <=> ai.embed('vehicle')) <
       (ai.embed('car') <=> ai.embed('tree'))
       AS category_similarity;
