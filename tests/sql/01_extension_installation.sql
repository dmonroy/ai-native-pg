-- Test 01: Extension Installation

\set ON_ERROR_STOP on

-- Extension is available
SELECT COUNT(*) = 1 AS extension_available
FROM pg_available_extensions WHERE name = 'ai';

-- Extension is loaded
SELECT COUNT(*) = 1 AS extension_loaded
FROM pg_extension WHERE extname = 'ai';

-- embed function exists
SELECT COUNT(*) = 1 AS embed_exists
FROM pg_proc WHERE proname = 'embed';

-- health_check function exists
SELECT COUNT(*) = 1 AS health_check_exists
FROM pg_proc WHERE proname = 'health_check';

-- Functions are in ai schema
SELECT COUNT(*) = 2 AS functions_in_ai_schema
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'ai' AND p.proname IN ('embed', 'health_check');
