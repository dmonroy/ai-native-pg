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

-- Happy closer to joyful than to sad
SELECT (ai.embed('happy') <=> ai.embed('joyful')) <
       (ai.embed('happy') <=> ai.embed('sad'))
       AS emotion_similarity;

-- Car closer to vehicle than to tree
SELECT (ai.embed('car') <=> ai.embed('vehicle')) <
       (ai.embed('car') <=> ai.embed('tree'))
       AS category_similarity;
