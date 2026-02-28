#!/bin/bash
# SQL Test Suite Runner
# Executes all SQL test files in order and reports results

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="${CONTAINER_NAME:-ai-native-pg-test}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-postgres}"
TEST_DIR="$(dirname "$0")/sql"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}Error: Container '${CONTAINER_NAME}' is not running${NC}"
    echo "Start it with: docker run -d --name ${CONTAINER_NAME} -e POSTGRES_PASSWORD=postgres ai-native-pg:latest"
    exit 1
fi

# Wait for PostgreSQL to be ready
echo -e "${BLUE}Waiting for PostgreSQL to be ready...${NC}"
for i in {1..30}; do
    if docker exec "${CONTAINER_NAME}" pg_isready -U "${DB_USER}" > /dev/null 2>&1; then
        echo -e "${GREEN}PostgreSQL is ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}Timeout waiting for PostgreSQL${NC}"
        exit 1
    fi
    sleep 1
done

# Give extension time to initialize
sleep 2

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  AI Extension SQL Test Suite  ${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Find all SQL test files
TEST_FILES=$(find "${TEST_DIR}" -name "*.sql" | sort)

if [ -z "${TEST_FILES}" ]; then
    echo -e "${RED}No test files found in ${TEST_DIR}${NC}"
    exit 1
fi

# Count tests
TOTAL_TESTS=$(echo "${TEST_FILES}" | wc -l)
PASSED_TESTS=0
FAILED_TESTS=0

# Run each test
for test_file in ${TEST_FILES}; do
    test_name=$(basename "${test_file}")

    echo -e "${YELLOW}Running: ${test_name}${NC}"

    # Run the test
    if docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -f - < "${test_file}" > /tmp/test_output.txt 2>&1; then
        echo -e "${GREEN}✓ ${test_name} passed${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))

        # Show any notices from the test
        grep "NOTICE:" /tmp/test_output.txt | sed 's/^NOTICE:  /  ℹ️  /' || true
    else
        echo -e "${RED}✗ ${test_name} failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))

        # Show error details
        echo -e "${RED}Error details:${NC}"
        cat /tmp/test_output.txt | grep -A 5 "ERROR:" || cat /tmp/test_output.txt
    fi

    echo ""
done

# Summary
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}        Test Summary            ${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "Total tests:  ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:       ${PASSED_TESTS}${NC}"

if [ ${FAILED_TESTS} -gt 0 ]; then
    echo -e "${RED}Failed:       ${FAILED_TESTS}${NC}"
    echo ""
    echo -e "${RED}✗ Test suite failed${NC}"
    exit 1
else
    echo -e "${GREEN}Failed:       0${NC}"
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
fi
