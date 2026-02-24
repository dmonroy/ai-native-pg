# AI-Native Postgres - C Extension

**Status:** Working Implementation
**Goal:** Provide IMMUTABLE embedding functions with generated columns support

## What This Extension Provides

1. ✅ Loading ONNX model at `_PG_init()` (once per backend)
2. ✅ IMMUTABLE function (enables generated columns)
3. ✅ Lazy loading (model loaded on first use)
4. ✅ BERT WordPiece tokenization (full implementation)
5. ✅ ONNX Runtime inference (complete)
6. ✅ Input validation and security checks
7. ✅ Comprehensive test suite (15 tests)

## Quick Start

```bash
# Build and test (runs full test suite)
./build-and-test.sh

# Or manually:

# Build image
docker build -t ai-postgres:latest .

# Run container
docker run -d \
  --name ai-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  ai-postgres:latest

# Connect
psql -h localhost -U postgres

# Test extension
SELECT ai.health_check();

# Generate embeddings
SELECT vector_dims(ai.embed('Hello world'));  -- Returns: 384
SELECT ai.embed('PostgreSQL') <=> ai.embed('database');  -- Cosine distance
```

## Architecture

```
PostgreSQL 18
├─ pgvector (vector type, HNSW indexes)
├─ ONNX Runtime 1.24.2 (CPU only)
└─ ai extension
   ├─ ai.c (C implementation)
   ├─ ai--1.0.sql (SQL definitions)
   └─ Model: bge-small-en-v1.5 (384-dim, ~64MB)
```

## Build Configuration

All versions are parameterized as Docker build arguments (see BUILD.md):

```bash
docker build \
  --build-arg PG_MAJOR=18 \
  --build-arg ONNX_VERSION=1.24.2 \
  -t ai-postgres:latest .
```

## Directory Structure

```
ai-native-pg-c/
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
- [x] Dockerfile with Postgres 18 + pgvector + ONNX Runtime
- [x] C extension with full functionality
- [x] Lazy loading architecture
- [x] Health check function
- [x] Input validation and security
  - UTF-8 validation
  - Null byte detection
  - Path traversal protection
  - File access validation
- [x] BERT WordPiece tokenization
- [x] ONNX Runtime inference
- [x] Vector conversion (float[] → pgvector format)
- [x] Generated column support (IMMUTABLE function)
- [x] Comprehensive test suite (15 tests)

### 📝 TODO (Future Enhancements)
1. Support multiple embedding models
2. Add batching for multiple embeddings
3. GPU support via ONNX Runtime
4. Model registry for dynamic loading
5. Performance optimizations
6. Production error handling improvements

## Using Generated Columns

```sql
-- Create table with generated embedding column
CREATE TABLE docs (
  id SERIAL PRIMARY KEY,
  content TEXT,
  embedding vector(384) GENERATED ALWAYS AS (ai.embed(content)) STORED
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

## Memory Usage

```
Per backend process:
- ONNX Runtime initialized: ~5MB
- Model NOT loaded: ~5MB
- Model loaded (on first ai.embed() call): ~64MB

With 10 connections:
- If no one calls ai.embed(): 10 × 5MB = 50MB
- If all call ai.embed(): 10 × 64MB = 640MB

Use PgBouncer for connection pooling in production!
```

## Known Limitations

1. **Single model only** (bge-small-en-v1.5)
2. **No batching** (one embedding at a time)
3. **CPU only** (no GPU support)
4. **No model registry** (hardcoded model path)
5. **Memory per backend** (~64MB when model is loaded)

## Testing

Run the comprehensive test suite:

```bash
./build-and-test.sh
```

This runs 15 SQL-based tests covering:
- Extension installation
- Basic embedding operations
- NULL and edge case handling
- Semantic similarity
- Query and search operations
- Input validation
- Concurrent operations
- Real-world scenarios

## References

- [ONNX Runtime C API](https://onnxruntime.ai/docs/api/c/)
- [PostgreSQL Extension Guide](https://www.postgresql.org/docs/current/extend-extensions.html)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [bge-small-en-v1.5 Model](https://huggingface.co/BAAI/bge-small-en-v1.5)
