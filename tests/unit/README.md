# C Unit Tests

This directory contains unit tests written in C that test the AI extension functions directly without requiring a running PostgreSQL instance.

## Structure

```
tests/unit/
├── README.md              # This file
├── Makefile              # Build configuration for unit tests
├── test_framework.h      # Simple test framework macros
├── test_framework.c      # Test framework implementation
├── test_embedding.c      # Tests for embedding functions
├── test_cache.c          # Tests for category cache
├── test_similarity.c     # Tests for cosine similarity
└── run_tests.sh          # Script to compile and run all tests
```

## Test Framework

The test framework provides simple assertion macros:

```c
#include "test_framework.h"

TEST(test_name) {
    // Test code
    ASSERT_EQ(expected, actual);
    ASSERT_TRUE(condition);
    ASSERT_FALSE(condition);
    ASSERT_NULL(pointer);
    ASSERT_NOT_NULL(pointer);
    ASSERT_FLOAT_EQ(expected, actual, epsilon);
}

int main() {
    RUN_TEST(test_name);
    return TEST_SUMMARY();
}
```

## Running Tests

```bash
# Run all tests
./run_tests.sh

# Run specific test
make test_embedding
./test_embedding

# Clean build artifacts
make clean
```

## Purpose

Unit tests serve several purposes:

1. **Fast Feedback**: Test C functions directly without PostgreSQL startup overhead
2. **Isolation**: Test individual functions in isolation
3. **Memory Debugging**: Use valgrind/sanitizers to catch memory issues
4. **Performance**: Benchmark individual functions
5. **Development**: Rapid iteration during development

## Integration with SQL Tests

These unit tests complement (not replace) the SQL integration tests:

- **Unit tests**: Test C functions, algorithms, edge cases
- **SQL tests**: Test PostgreSQL integration, SQL API, end-to-end workflows

Both test suites should pass before committing changes.

## Test Coverage Goals

- [ ] Embedding computation
- [ ] Cosine similarity calculation
- [ ] Category cache operations (insert, lookup, stats)
- [ ] Input validation
- [ ] Memory allocation and cleanup
- [ ] Edge cases (empty strings, NULL handling, boundaries)
- [ ] Performance benchmarks

## Dependencies

Unit tests should minimize dependencies:
- Standard C library
- ONNX Runtime (for embedding tests)
- pgvector extension headers (for Vector type)
- Test framework (included)

PostgreSQL headers should be mocked or abstracted where possible to allow testing without full PostgreSQL installation.

## Future Enhancements

- [ ] Code coverage reporting (gcov/llvm-cov)
- [ ] Memory leak detection (valgrind integration)
- [ ] Address sanitizer support
- [ ] Fuzzing harness for input validation
- [ ] Performance regression tracking
- [ ] CI/CD integration
