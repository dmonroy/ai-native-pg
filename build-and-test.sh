#!/bin/bash
# Build and Test Script for AI PostgreSQL Extension

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}AI PostgreSQL - Build & Test${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Configuration
IMAGE_NAME="${IMAGE_NAME:-ai-postgres:test}"
CONTAINER_NAME="ai-postgres-test"
TEST_USER="postgres"
TEST_PASSWORD="postgres"
TEST_PORT="5434"

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
}

# Trap cleanup on exit
trap cleanup EXIT

echo -e "${YELLOW}Step 1: Building Docker image...${NC}"
if docker build -t $IMAGE_NAME . > /tmp/build.log 2>&1; then
    echo -e "${GREEN}✓ Build successful${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    tail -20 /tmp/build.log
    exit 1
fi
echo ""

echo -e "${YELLOW}Step 2: Starting PostgreSQL container...${NC}"
docker run -d \
    --name $CONTAINER_NAME \
    -e POSTGRES_PASSWORD=$TEST_PASSWORD \
    -p $TEST_PORT:5432 \
    $IMAGE_NAME > /dev/null

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}Waiting for PostgreSQL to start...${NC}"
for i in {1..30}; do
    if docker exec $CONTAINER_NAME pg_isready -U $TEST_USER > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL ready${NC}"
        break
    fi
    echo -n "."
    sleep 1
    if [ $i -eq 30 ]; then
        echo -e "${RED}✗ Timeout waiting for PostgreSQL${NC}"
        exit 1
    fi
done
echo ""

# Give extension time to initialize
sleep 2

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}     Running Test Suite        ${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Run SQL tests
PASSED=0
FAILED=0

for test_file in tests/sql/*.sql; do
    if [ ! -f "$test_file" ]; then
        echo -e "${RED}No test files found in tests/sql/${NC}"
        exit 1
    fi

    test_name=$(basename "$test_file" .sql)
    echo -e "${YELLOW}Running: ${test_name}${NC}"

    # Run test and capture output
    if output=$(cat "$test_file" | docker exec -i $CONTAINER_NAME psql -U $TEST_USER 2>&1); then
        # Check if any assertions failed (look for 'f' in boolean results)
        if echo "$output" | grep -q "^ f$"; then
            echo -e "${RED}✗ ${test_name} - Assertion failed${NC}"
            echo "$output" | grep -B2 " f$"
            FAILED=$((FAILED + 1))
        else
            echo -e "${GREEN}✓ ${test_name} passed${NC}"
            PASSED=$((PASSED + 1))
        fi
    else
        echo -e "${RED}✗ ${test_name} - Error occurred${NC}"
        echo "$output" | grep "ERROR:" | head -5
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

# Summary
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}        Test Summary            ${NC}"
echo -e "${BLUE}================================${NC}"
TOTAL=$((PASSED + FAILED))
echo -e "Total:  ${TOTAL}"
echo -e "${GREEN}Passed: ${PASSED}${NC}"

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED}${NC}"
    echo ""
    echo -e "${RED}✗ Test suite failed${NC}"
    exit 1
else
    echo -e "${GREEN}Failed: 0${NC}"
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
fi
