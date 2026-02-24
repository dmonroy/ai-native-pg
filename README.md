# AI-Native Postgres - Proof of Concept

**Status:** Experimental PoC
**Goal:** Prove that IMMUTABLE embedding functions with generated columns work

## What This PoC Demonstrates

1. ✅ Loading ONNX model at `_PG_init()` (once per backend)
2. ✅ IMMUTABLE function (enables generated columns)
3. ✅ Lazy loading (model loaded on first use)
4. ⚠️ Tokenization (placeholder - needs proper BERT tokenizer)
5. ⚠️ ONNX inference (skeleton - needs implementation)

## Quick Start

```bash
# Build image
docker build -t ai-postgres:poc .

# Run container
docker run -d \
  --name ai-postgres-poc \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  ai-postgres:poc

# Connect
psql -h localhost -U postgres

# Test extension
SELECT ai.health_check();
SELECT ai.version();

# This will fail with "not yet implemented" (expected for PoC skeleton)
SELECT ai.embed('Hello world');
```

## Architecture

```
PostgreSQL 18
├─ pgvector (vector type, HNSW indexes)
├─ ONNX Runtime 1.18.0 (CPU only)
└─ ai extension
   ├─ ai.c (C implementation)
   ├─ ai--1.0.sql (SQL definitions)
   └─ Model: bge-small-en-v1.5 (384-dim, ~64MB)
```

## Directory Structure

```
ai-native-pg/
├── Dockerfile              # Container definition
├── init.sql                # Auto-run on container start
├── README.md              # This file
├── ai_extension/
│   ├── Makefile           # Build configuration
│   ├── ai.control         # Extension metadata
│   ├── ai--1.0.sql        # SQL function definitions
│   └── ai.c               # C implementation
└── test.sql               # Test queries
```

## Current Status

### ✅ Implemented
- [x] Dockerfile with Postgres 18 + pgvector + ONNX Runtime
- [x] C extension skeleton
- [x] Lazy loading architecture
- [x] Health check function
- [x] Input validation

### ⚠️ Placeholder
- [ ] Tokenization (needs proper BERT WordPiece tokenizer)
- [ ] ONNX inference (skeleton only)
- [ ] Vector conversion (float[] → pgvector format)

### 📝 TODO (Next Steps)
1. Implement proper BERT tokenizer
2. Implement ONNX inference
3. Convert embeddings to pgvector format
4. Test with generated columns
5. Benchmark performance

## Testing Generated Columns

Once inference is implemented:

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

## Known Limitations (PoC)

1. **Single model only** (bge-small-en-v1.5)
2. **Placeholder tokenizer** (not production-ready)
3. **No proper error handling** (minimal for PoC)
4. **No batching** (one embedding at a time)
5. **CPU only** (no GPU support)
6. **No model registry** (hardcoded model path)

## Next Steps After PoC

1. **Phase 1:** Complete ONNX inference
2. **Phase 2:** Add proper BERT tokenizer
3. **Phase 3:** Test generated columns at scale
4. **Phase 4:** Add multiple models
5. **Phase 5:** Build model registry
6. **Phase 6:** Optimize performance (batching, etc.)

## References

- [ONNX Runtime C API](https://onnxruntime.ai/docs/api/c/)
- [PostgreSQL Extension Guide](https://www.postgresql.org/docs/current/extend-extensions.html)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [bge-small-en-v1.5 Model](https://huggingface.co/BAAI/bge-small-en-v1.5)
