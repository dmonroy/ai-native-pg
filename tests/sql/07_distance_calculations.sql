-- Test 07: Distance Calculations

\set ON_ERROR_STOP on

-- Distance returns numeric value
SELECT pg_typeof(ai.embed('cat') <=> ai.embed('dog')) = 'double precision'::regtype
       AS distance_is_numeric;

-- Distance is non-negative
SELECT (ai.embed('hello') <=> ai.embed('world')) >= 0
       AS distance_non_negative;

-- Distance to self is zero (or very close)
SELECT (ai.embed('test') <=> ai.embed('test')) < 0.0001
       AS distance_to_self_zero;

-- Distance is symmetric (A to B = B to A)
SELECT abs(
    (ai.embed('cat') <=> ai.embed('dog')) -
    (ai.embed('dog') <=> ai.embed('cat'))
) < 0.0001 AS distance_symmetric;

-- Triangle inequality holds (roughly)
-- d(A,C) <= d(A,B) + d(B,C)
SELECT (ai.embed('cat') <=> ai.embed('animal')) <=
       (ai.embed('cat') <=> ai.embed('dog')) +
       (ai.embed('dog') <=> ai.embed('animal')) + 0.01
       AS triangle_inequality;
