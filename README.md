# AI-Native Postgres - C Extension

**Status:** Experimental Implementation
**Goal:** Provide IMMUTABLE embedding and classification functions with generated columns support

## What This Extension Provides

1. ✅ Loading ONNX model at `_PG_init()` (once per backend)
2. ✅ IMMUTABLE functions (enables generated columns and indexes)
3. ✅ Lazy loading (model loaded on first use)
4. ✅ BERT WordPiece tokenization (full implementation)
5. ✅ ONNX Runtime inference (complete)
6. ✅ Input validation and security checks
7. ✅ Category embedding cache (10-100× speedup for classification)
8. ✅ Comprehensive test suite (20 SQL tests + 7 C unit tests)

## Docker Images

Pre-built multi-architecture images (linux/amd64, linux/arm64) are available on GitHub Container Registry:

```bash
# Latest PostgreSQL (18)
docker pull ghcr.io/dmonroy/ai-native-pg:dev

# Specific PostgreSQL versions
docker pull ghcr.io/dmonroy/ai-native-pg:pg18-dev
docker pull ghcr.io/dmonroy/ai-native-pg:pg17-dev
docker pull ghcr.io/dmonroy/ai-native-pg:pg16-dev
docker pull ghcr.io/dmonroy/ai-native-pg:pg15-dev
docker pull ghcr.io/dmonroy/ai-native-pg:pg14-dev
```

All images include:
- PostgreSQL (versions 14-18)
- pgvector extension
- ONNX Runtime 1.24.2
- ai extension with nomic-embed-text-v1.5 model

## Quick Start

```bash
# Pull and run the latest version (PostgreSQL 18)
docker pull ghcr.io/dmonroy/ai-native-pg:dev

docker run -d \
  --name ai-native-pg \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  ghcr.io/dmonroy/ai-native-pg:dev

# Connect
psql -h localhost -U postgres

# Test extension
SELECT ai.health_check();

# Generate embeddings
SELECT vector_dims(ai.embed('Hello world'));  -- Returns: 768
SELECT ai.embed('PostgreSQL') <=> ai.embed('database');  -- Cosine distance

# Classify content
SELECT ai.classify('PostgreSQL database', ARRAY['technology', 'sports', 'cooking']);
-- Returns: 'technology'
```

## Architecture

```
PostgreSQL 18
├─ pgvector (vector type, HNSW indexes)
├─ ONNX Runtime 1.24.2 (CPU only)
└─ ai extension
   ├─ ai.c (C implementation with category cache)
   ├─ ai--1.0.sql (SQL definitions)
   └─ Model: nomic-embed-text-v1.5 (768-dim, ~64MB, MTEB 62.28)
```

## Building from Source

Pre-built images are recommended, but you can build locally:

```bash
# Build and test (runs full test suite)
./build-and-test.sh

# Or build manually with specific versions
docker build \
  --build-arg PG_MAJOR=18 \
  --build-arg ONNX_VERSION=1.24.2 \
  -t ai-native-pg:latest .
```

All versions are parameterized as Docker build arguments (see BUILD.md).

## Directory Structure

```
ai-native-pg/               # Repository root
├── Dockerfile              # Container definition
├── BUILD.md               # Build configuration docs
├── README.md              # This file
├── build-and-test.sh      # Build and test automation
├── ai_extension/
│   ├── Makefile           # Build configuration
│   ├── ai.control         # Extension metadata
│   ├── ai--1.0.sql        # SQL function definitions
│   └── ai.c               # C implementation
└── tests/
    ├── README.md          # Test documentation
    └── sql/               # SQL test files (15 tests)
```

## Current Status

### ✅ Implemented

**Core Functions:**
- [x] `ai.embed(text)` - Generate 768-dim embeddings (IMMUTABLE)
- [x] `ai.classify(text, text[])` - Classify into categories (5 variants)
- [x] `ai.health_check()` - System health verification
- [x] `ai.classify_cache_stats()` - Cache performance monitoring
- [x] `ai.version()` - Extension version

**Infrastructure:**
- [x] Dockerfile with Postgres 18 + pgvector + ONNX Runtime
- [x] C extension with category embedding cache
- [x] Lazy loading architecture (model loads on first use)
- [x] Input validation and security
  - UTF-8 validation
  - Null byte detection
  - Path traversal protection
  - File access validation
- [x] BERT WordPiece tokenization
- [x] ONNX Runtime inference
- [x] Vector conversion (float[] → pgvector format)
- [x] Generated column support (IMMUTABLE functions)
- [x] Comprehensive test suite (20 SQL tests + 7 C unit tests)

### 📝 TODO (Future Enhancements)
1. Support multiple embedding models
2. Add batching for multiple embeddings
3. GPU support via ONNX Runtime
4. Model registry for dynamic loading
5. Performance optimizations
6. Production error handling improvements

## Core Functions

### Embedding Generation

```sql
-- Generate embeddings (768-dimensional vectors)
SELECT ai.embed('Hello world');

-- Use in semantic search
SELECT content, 1 - (embedding <=> ai.embed('query')) as similarity
FROM docs
ORDER BY embedding <=> ai.embed('query')
LIMIT 10;
```

### Classification (5 Variants)

```sql
-- 1. Basic classification - returns single best match
SELECT ai.classify('PostgreSQL database', ARRAY['technology', 'sports', 'cooking']);
-- Returns: 'technology'

-- 2. With confidence threshold - returns NULL if below threshold
SELECT ai.classify(
  'Maybe about tech?',
  ARRAY['technology', 'sports'],
  0.8  -- threshold
);
-- Returns: 'technology' or NULL (if similarity < 0.8)

-- 3. Multi-label - returns top K matches
SELECT ai.classify(
  'Database systems and AI',
  ARRAY['technology', 'ai', 'sports', 'cooking'],
  2  -- top_k
);
-- Returns: ['technology', 'ai']

-- 4. Combined threshold + top_k
SELECT ai.classify(
  'PostgreSQL with AI features',
  ARRAY['database', 'ai', 'sports'],
  0.6,  -- threshold
  2     -- top_k
);
-- Returns: ['database', 'ai'] (only those above 0.6 similarity)

-- 5. Type-safe enum classification
CREATE TYPE content_type AS ENUM ('technology', 'sports', 'cooking');
SELECT ai.classify('PostgreSQL', NULL::content_type);
-- Returns: 'technology'::content_type
```

## Using Generated Columns

```sql
-- Create table with generated embedding column
CREATE TABLE docs (
  id SERIAL PRIMARY KEY,
  content TEXT,
  embedding vector(768) GENERATED ALWAYS AS (ai.embed(content)) STORED
);

-- Insert data (embeddings auto-generated)
INSERT INTO docs (content) VALUES
  ('PostgreSQL is a powerful database'),
  ('AI-native features in databases'),
  ('Vector similarity search');

-- Create HNSW index
CREATE INDEX ON docs USING hnsw (embedding vector_cosine_ops);

-- Semantic search
SELECT content
FROM docs
ORDER BY embedding <=> ai.embed('database systems')
LIMIT 3;
```

### Classification with Generated Columns

```sql
-- Auto-categorize content on INSERT
CREATE TABLE articles (
  id SERIAL PRIMARY KEY,
  content TEXT,
  category TEXT GENERATED ALWAYS AS (
    ai.classify(content, ARRAY['technology', 'sports', 'business', 'science'])
  ) STORED
);

-- Create index on category
CREATE INDEX ON articles(category);

-- Insert and auto-classify
INSERT INTO articles (content) VALUES
  ('PostgreSQL adds AI features'),
  ('Lakers win championship'),
  ('Stock market reaches new high');

-- Query by category (uses index)
SELECT * FROM articles WHERE category = 'technology';
```

## Performance Features

### Category Embedding Cache

The extension caches category embeddings to avoid redundant computation:

```sql
-- First classification with new categories (cache miss)
SELECT ai.classify('text', ARRAY['cat1', 'cat2', 'cat3']);
-- Time: ~30ms (embeds content + 3 categories)

-- Subsequent classifications with same categories (cache hit)
SELECT ai.classify('different text', ARRAY['cat1', 'cat2', 'cat3']);
-- Time: ~6ms (only embeds content, categories cached)

-- Check cache performance
SELECT * FROM ai.classify_cache_stats();
```

**Cache benefits:**
- 10-100× speedup for repeated categories
- Per-backend process (no locking needed)
- Automatic cleanup on connection close

## Memory Usage

```
Per backend process:
- ONNX Runtime initialized: ~5MB
- Model NOT loaded: ~5MB
- Model loaded (on first ai.embed() call): ~64MB
- Category cache: ~2KB per cached category

With 10 connections:
- If no one calls ai.embed(): 10 × 5MB = 50MB
- If all call ai.embed(): 10 × 64MB = 640MB
- Plus category cache: ~2MB typical (1000 categories × 10 connections)

Use PgBouncer for connection pooling in production!
```

## Known Limitations

1. **Single model only** (nomic-embed-text-v1.5)
2. **No batching** (one embedding at a time)
3. **CPU only** (no GPU support)
4. **No model registry** (hardcoded model path)
5. **Memory per backend** (~64MB when model is loaded)
6. **Experimental status** (API may change)

## Testing

Run the comprehensive test suite:

```bash
./build-and-test.sh
```

This runs **20 SQL tests** and **7 C unit tests** covering:

**SQL Tests:**
- Extension installation and health checks
- Basic embedding operations
- NULL and edge case handling
- Semantic similarity calculations
- Query and search operations
- Input validation
- Concurrent operations
- Category embedding cache
- Classification (5 variants: basic, threshold, top-k, combined, enum)
- Real-world scenarios

**C Unit Tests:**
- Similarity calculations
- Tokenization
- Memory management

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

Copyright 2026 Darwin Monroy

## References

- [ONNX Runtime C API](https://onnxruntime.ai/docs/api/c/)
- [PostgreSQL Extension Guide](https://www.postgresql.org/docs/current/extend-extensions.html)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [nomic-embed-text-v1.5 Model](https://huggingface.co/nomic-ai/nomic-embed-text-v1.5)
