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

-- Version function
CREATE FUNCTION ai.version() RETURNS text
  IMMUTABLE
  LANGUAGE SQL
  AS $$ SELECT '1.0-poc'::text; $$;

COMMENT ON SCHEMA ai IS 'AI-native primitives for PostgreSQL';
COMMENT ON FUNCTION ai.embed(text) IS 'Generate embedding using nomic-embed-text-v1.5 (768-dim, MTEB 62.28)';
COMMENT ON FUNCTION ai.health_check() IS 'Check if ONNX model is loaded and working';
COMMENT ON FUNCTION ai.classify_cache_stats() IS 'Get category embedding cache statistics (hits, misses, entries, memory)';
