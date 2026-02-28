# SQL Test Suite

Assertion-based SQL test suite for the AI PostgreSQL extension. Tests are written in pure SQL with built-in assertions that raise exceptions on failure.

## Test Files

| Test | File | Description |
|------|------|-------------|
| 01 | `01_extension_installation.sql` | Extension loading and function registration |
| 02 | `02_health_check.sql` | Health check function validation |
| 03 | `03_basic_embedding.sql` | Basic embed() functionality and 384-dim output |
| 04 | `04_edge_cases.sql` | NULL, empty string, long text, special chars |
| 05 | `05_semantic_similarity.sql` | Semantic similarity and distance calculations |
| 06 | `06_immutable_function.sql` | IMMUTABLE property and generated columns |
| 07 | `07_performance.sql` | Batch operations and determinism |

## Running Tests

### Automated Test Runner

```bash
# With default container name
./tests/run_tests.sh

# With custom container
CONTAINER_NAME=my-postgres ./tests/run_tests.sh
```

### Individual Test

```bash
# Run a specific test
docker exec ai-native-pg-test psql -U postgres -f - < tests/sql/03_basic_embedding.sql

# Or copy into container and run
docker cp tests/sql/03_basic_embedding.sql ai-native-pg-test:/tmp/
docker exec ai-native-pg-test psql -U postgres -f /tmp/03_basic_embedding.sql
```

### Manual Testing

```bash
# Connect to container
docker exec -it ai-native-pg-test psql -U postgres

# Paste test content or run:
\i /path/to/test.sql
```

## Test Structure

Each test file follows this pattern:

```sql
-- Test Description
\set ON_ERROR_STOP on

\echo '=== Test N: Test Name ==='

-- Test assertions using DO blocks
DO $$
BEGIN
    -- Test logic here
    IF condition_fails THEN
        RAISE EXCEPTION 'Descriptive error message';
    END IF;

    RAISE NOTICE 'Success message with details';
END $$;

\echo '✓ Test N passed: Summary'
```

### Assertion Patterns

**Check for NULL:**
```sql
IF result IS NULL THEN
    RAISE EXCEPTION 'Expected non-NULL, got NULL';
END IF;
```

**Check value:**
```sql
IF value != expected THEN
    RAISE EXCEPTION 'Expected %, got %', expected, value;
END IF;
```

**Check existence:**
```sql
IF NOT EXISTS (SELECT ...) THEN
    RAISE EXCEPTION 'Record not found';
END IF;
```

**Verify error is raised:**
```sql
DECLARE
    error_raised boolean := false;
BEGIN
    BEGIN
        -- Code that should error
    EXCEPTION WHEN OTHERS THEN
        error_raised := true;
    END;

    IF NOT error_raised THEN
        RAISE EXCEPTION 'Expected error but none raised';
    END IF;
END;
```

## Output

### Successful Test
```
=== Test 3: Basic Embedding ===
NOTICE:  embed() returned valid 384-dimensional vector
NOTICE:  Different inputs produce different embeddings (distance: 0.123)
✓ Test 3 passed: Basic embedding works correctly
```

### Failed Test
```
=== Test 3: Basic Embedding ===
ERROR:  Expected 384 dimensions, got 512
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Build Docker image
        run: docker build -t ai-native-pg:test .

      - name: Start PostgreSQL
        run: |
          docker run -d --name ai-native-pg-test \
            -e POSTGRES_PASSWORD=postgres \
            ai-native-pg:test
          sleep 5

      - name: Run test suite
        run: ./tests/run_tests.sh

      - name: Cleanup
        if: always()
        run: docker rm -f ai-native-pg-test
```

### GitLab CI

```yaml
test:
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker build -t ai-native-pg:test .
    - docker run -d --name ai-native-pg-test -e POSTGRES_PASSWORD=postgres ai-native-pg:test
    - sleep 5
    - ./tests/run_tests.sh
  after_script:
    - docker rm -f ai-native-pg-test
```

## Adding New Tests

1. **Create test file:** `tests/sql/NN_test_name.sql`
2. **Follow naming convention:** Use sequential numbering
3. **Use assertions:** Raise exceptions on failure
4. **Add documentation:** Describe what the test validates
5. **Test locally:** Run individually before committing

### Template

```sql
-- Test N: Description
-- What this test validates

\set ON_ERROR_STOP on

\echo '=== Test N: Test Name ==='

DO $$
DECLARE
    -- Variables
BEGIN
    -- Test logic

    IF NOT condition THEN
        RAISE EXCEPTION 'Test failed: reason';
    END IF;

    RAISE NOTICE 'Test passed: details';
END $$;

\echo '✓ Test N passed: Summary'
```

## Debugging Failed Tests

### Enable verbose output

```bash
# Show all SQL output
docker exec ai-native-pg-test psql -U postgres -a -f - < tests/sql/03_basic_embedding.sql
```

### Check PostgreSQL logs

```bash
# View container logs
docker logs ai-native-pg-test

# Follow logs in real-time
docker logs -f ai-native-pg-test
```

### Interactive debugging

```bash
# Connect and run commands manually
docker exec -it ai-native-pg-test psql -U postgres

# Check extension status
SELECT * FROM pg_extension WHERE extname = 'ai';

# Test functions manually
SELECT ai.health_check();
SELECT vector_dims(ai.embed('test'));
```

## Best Practices

1. **Atomic tests:** Each test should be independent
2. **Cleanup:** Use TEMP tables or clean up after yourself
3. **Clear errors:** Use descriptive exception messages
4. **Document expected behavior:** Add comments explaining what should happen
5. **Test both success and failure:** Verify errors are raised when expected

## Performance

Tests run serially and take approximately:
- Individual test: 0.1-2 seconds
- Full suite: 5-15 seconds

Performance depends on:
- Model load time (first test only)
- Number of embeddings generated
- Container resources
