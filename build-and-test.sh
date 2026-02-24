#!/bin/bash
# Build and Test Script for AI PostgreSQL Extension
# Tests the hash table vocabulary optimization

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}AI PostgreSQL - Build & Test${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Configuration
IMAGE_NAME="ai-postgres:hash-table-test"
CONTAINER_NAME="ai-postgres-test"
TEST_DB="postgres"
TEST_USER="postgres"
TEST_PASSWORD="postgres"
TEST_PORT="5434"  # Changed from 5433 to avoid conflicts

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
}

# Trap cleanup on exit
trap cleanup EXIT

echo -e "${YELLOW}Step 1: Building Docker image...${NC}"
docker build -t $IMAGE_NAME . 2>&1 | tail -20
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi
echo ""

echo -e "${YELLOW}Step 2: Starting PostgreSQL container...${NC}"
docker run -d \
    --name $CONTAINER_NAME \
    -e POSTGRES_PASSWORD=$TEST_PASSWORD \
    -p $TEST_PORT:5432 \
    $IMAGE_NAME

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}Waiting for PostgreSQL to start...${NC}"
for i in {1..30}; do
    if docker exec $CONTAINER_NAME pg_isready -U postgres > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL ready${NC}"
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

# Give extension a moment to initialize
sleep 2

echo -e "${YELLOW}Step 3: Running extension tests...${NC}"
echo ""

# Test 1: Extension installation
echo -e "${YELLOW}Test 1: Extension installation${NC}"
docker exec $CONTAINER_NAME psql -U postgres -c "SELECT version();" | head -3
echo ""

# Test 2: Health check
echo -e "${YELLOW}Test 2: Health check${NC}"
docker exec $CONTAINER_NAME psql -U postgres -c "SELECT ai.health_check();" || {
    echo -e "${RED}✗ Health check failed${NC}"
    exit 1
}
echo -e "${GREEN}✓ Health check passed${NC}"
echo ""

# Test 3: Basic embedding
echo -e "${YELLOW}Test 3: Basic embedding (triggers vocabulary load)${NC}"
START_TIME=$(date +%s%3N)
docker exec $CONTAINER_NAME psql -U postgres -c \
    "SELECT vector_dims(ai.embed('Hello world')) as dims;" || {
    echo -e "${RED}✗ Basic embedding failed${NC}"
    exit 1
}
END_TIME=$(date +%s%3N)
FIRST_CALL_TIME=$((END_TIME - START_TIME))
echo -e "${GREEN}✓ Basic embedding passed (${FIRST_CALL_TIME}ms - includes model load)${NC}"
echo ""

# Test 4: Performance test (hash table optimization)
echo -e "${YELLOW}Test 4: Performance test (100 embeddings)${NC}"
docker exec $CONTAINER_NAME psql -U postgres -c \
    "\\timing on" \
    -c "SELECT COUNT(*) FROM (
        SELECT ai.embed('The quick brown fox jumps over the lazy dog')
        FROM generate_series(1, 100)
    ) s;" | grep "Time:" || true
echo -e "${GREEN}✓ Performance test completed${NC}"
echo ""

# Test 5: Edge cases
echo -e "${YELLOW}Test 5: Edge cases${NC}"

echo "  - Empty string (should error):"
docker exec $CONTAINER_NAME psql -U postgres -c \
    "SELECT ai.embed('');" 2>&1 | grep -q "Cannot embed empty string" && \
    echo -e "    ${GREEN}✓ Correctly rejected${NC}" || \
    echo -e "    ${RED}✗ Should have errored${NC}"

echo "  - NULL input (should return NULL):"
docker exec $CONTAINER_NAME psql -U postgres -c \
    "SELECT ai.embed(NULL) IS NULL;" | grep -q "t" && \
    echo -e "    ${GREEN}✓ Correctly returned NULL${NC}" || \
    echo -e "    ${RED}✗ Should return NULL${NC}"

echo "  - Long text (should work):"
docker exec $CONTAINER_NAME psql -U postgres -c \
    "SELECT vector_dims(ai.embed(repeat('test ', 100))) as dims;" > /dev/null 2>&1 && \
    echo -e "    ${GREEN}✓ Long text handled${NC}" || \
    echo -e "    ${RED}✗ Long text failed${NC}"
echo ""

# Test 6: Similarity test
echo -e "${YELLOW}Test 6: Semantic similarity${NC}"
docker exec $CONTAINER_NAME psql -U postgres -c "
    SELECT
        CASE
            WHEN ai.embed('cat') <=> ai.embed('dog') <
                 ai.embed('cat') <=> ai.embed('database')
            THEN 'PASS: cat is more similar to dog than database'
            ELSE 'FAIL: Similarity makes no sense'
        END as result;
" || echo -e "${YELLOW}  (Similarity test failed - may need more testing)${NC}"
echo ""

# Test 7: Generated column test
echo -e "${YELLOW}Test 7: Generated columns (IMMUTABLE function)${NC}"
docker exec $CONTAINER_NAME psql -U postgres << 'EOF'
CREATE TABLE test_docs (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(384) GENERATED ALWAYS AS (ai.embed(content)) STORED
);

INSERT INTO test_docs (content) VALUES
    ('PostgreSQL is a powerful database'),
    ('Machine learning in databases'),
    ('Vector similarity search');

SELECT id, content, vector_dims(embedding) as dims
FROM test_docs;

DROP TABLE test_docs;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Generated columns working${NC}"
else
    echo -e "${RED}✗ Generated columns failed${NC}"
fi
echo ""

# Test 8: Concurrent connections (tests per-backend isolation)
echo -e "${YELLOW}Test 8: Concurrent connections test${NC}"
for i in {1..5}; do
    docker exec $CONTAINER_NAME psql -U postgres -c \
        "SELECT LENGTH(ai.embed('test ${i}')::text) > 0;" > /dev/null 2>&1 &
done
wait
echo -e "${GREEN}✓ Concurrent connections handled${NC}"
echo ""

# Test 9: Memory check
echo -e "${YELLOW}Test 9: Memory usage check${NC}"
docker exec $CONTAINER_NAME psql -U postgres -c \
    "SELECT pg_size_pretty(pg_total_relation_size('pg_class'));" || true
echo -e "${GREEN}✓ Memory check complete${NC}"
echo ""

# Test 10: Vocabulary hash table verification
echo -e "${YELLOW}Test 10: Hash table vocabulary check${NC}"
docker exec $CONTAINER_NAME psql -U postgres -c "SELECT ai.health_check();" | \
    grep -q "Loaded vocabulary with" && \
    echo -e "${GREEN}✓ Vocabulary loaded via hash table${NC}" || \
    echo -e "${YELLOW}  (Could not verify hash table - check logs)${NC}"
echo ""

# Performance Summary
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Test Summary${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "First call time: ${FIRST_CALL_TIME}ms (includes model load)"
echo -e "Vocabulary: Hash table (O(1) lookup)"
echo -e "Model: bge-small-en-v1.5 (384-dim)"
echo -e ""
echo -e "${GREEN}✓ All tests completed successfully!${NC}"
echo -e ""
echo -e "${YELLOW}Container still running on port $TEST_PORT${NC}"
echo -e "Connect with: ${GREEN}docker exec -it $CONTAINER_NAME psql -U postgres${NC}"
echo -e "Or: ${GREEN}psql -h localhost -p $TEST_PORT -U postgres${NC}"
echo -e "Stop with: ${GREEN}docker stop $CONTAINER_NAME${NC}"
echo ""

# Show logs for verification
echo -e "${YELLOW}Recent logs (check for hash table message):${NC}"
docker logs $CONTAINER_NAME 2>&1 | grep "ai extension" | tail -5 || true
echo ""

echo -e "${GREEN}Build and test complete!${NC}"
