#!/bin/bash
# Build and test AI-Postgres PoC

set -e

echo "=== Building AI-Postgres PoC ==="
docker build -t ai-postgres:poc .

echo ""
echo "=== Build complete! ==="
echo ""
echo "To run:"
echo "  docker run -d --name ai-postgres-poc -e POSTGRES_PASSWORD=postgres -p 5432:5432 ai-postgres:poc"
echo ""
echo "To connect:"
echo "  psql -h localhost -U postgres"
echo ""
echo "To test:"
echo "  psql -h localhost -U postgres -f test.sql"
