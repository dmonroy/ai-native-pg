-- AI Extension SQL definitions
-- Proof of Concept: Single model, IMMUTABLE function, generated columns

-- Create schema
CREATE SCHEMA IF NOT EXISTS ai;

-- Core embedding function (IMMUTABLE)
-- Uses nomic-embed-text-v1.5 loaded at _PG_init()
CREATE FUNCTION ai.embed(text) RETURNS vector
  IMMUTABLE           -- Safe because model loaded once at _PG_init()
  STRICT              -- Returns NULL for NULL input
  PARALLEL SAFE       -- Can run in parallel workers
  LANGUAGE C
  AS '$libdir/ai', 'ai_embed';

-- Health check function
CREATE FUNCTION ai.health_check() RETURNS text
  STABLE
  LANGUAGE C
  AS '$libdir/ai', 'ai_health_check';

-- Category cache statistics
-- Returns cache performance metrics for monitoring
CREATE FUNCTION ai.classify_cache_stats()
  RETURNS TABLE(hits bigint, misses bigint, entries bigint, memory_mb double precision)
  STABLE
  LANGUAGE C
  AS '$libdir/ai', 'ai_classify_cache_stats';

-- Classification function (array variant)
-- Classifies content into one of the provided categories using semantic similarity
CREATE FUNCTION ai.classify(text, text[]) RETURNS text
  IMMUTABLE           -- Deterministic: same input always returns same output
  STRICT              -- Returns NULL for NULL content (errors on NULL categories)
  PARALLEL SAFE       -- Can run in parallel workers
  LANGUAGE C
  AS '$libdir/ai', 'ai_classify_array';

-- Classification function with threshold
-- Returns best category only if similarity >= threshold, NULL otherwise
CREATE FUNCTION ai.classify(text, text[], double precision) RETURNS text
  IMMUTABLE           -- Deterministic: same input always returns same output
  PARALLEL SAFE       -- Can run in parallel workers
  LANGUAGE C
  AS '$libdir/ai', 'ai_classify_array_threshold';

-- Multi-label classification (top-K)
-- Returns top K most similar categories sorted by similarity
CREATE FUNCTION ai.classify(text, text[], integer) RETURNS text[]
  IMMUTABLE           -- Deterministic: same input always returns same output
  STRICT              -- Returns NULL for NULL content
  PARALLEL SAFE       -- Can run in parallel workers
  LANGUAGE C
  AS '$libdir/ai', 'ai_classify_array_topk';

-- Combined threshold + top-K classification
-- Returns top K categories that meet minimum similarity threshold
CREATE FUNCTION ai.classify(text, text[], double precision, integer) RETURNS text[]
  IMMUTABLE           -- Deterministic: same input always returns same output
  PARALLEL SAFE       -- Can run in parallel workers
  LANGUAGE C
  AS '$libdir/ai', 'ai_classify_array_threshold_topk';

-- Version function
CREATE FUNCTION ai.version() RETURNS text
  IMMUTABLE
  LANGUAGE SQL
  AS $$ SELECT '1.0-poc'::text; $$;

COMMENT ON SCHEMA ai IS 'AI-native primitives for PostgreSQL';
COMMENT ON FUNCTION ai.embed(text) IS 'Generate embedding using nomic-embed-text-v1.5 (768-dim, MTEB 62.28)';
COMMENT ON FUNCTION ai.health_check() IS 'Check if ONNX model is loaded and working';
COMMENT ON FUNCTION ai.classify_cache_stats() IS 'Get category embedding cache statistics (hits, misses, entries, memory)';
COMMENT ON FUNCTION ai.classify(text, text[]) IS 'Classify content into one of the provided categories using semantic similarity';
COMMENT ON FUNCTION ai.classify(text, text[], double precision) IS 'Classify content with minimum similarity threshold (0.0-1.0), returns NULL if below threshold';
COMMENT ON FUNCTION ai.classify(text, text[], integer) IS 'Multi-label classification: returns top K most similar categories sorted by similarity';
COMMENT ON FUNCTION ai.classify(text, text[], double precision, integer) IS 'Combined threshold + top-K: returns top K categories above threshold (may return fewer or empty array)';
