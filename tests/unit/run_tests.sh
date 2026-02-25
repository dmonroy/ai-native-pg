#!/bin/bash

# Run all unit tests for AI extension

set -e

echo "================================"
echo "   AI Extension Unit Tests"
echo "================================"
echo ""

# Build tests
echo "Building tests..."
make clean > /dev/null 2>&1
make all

echo ""
echo "================================"
echo "     Running Tests"
echo "================================"
echo ""

# Run tests
make test

echo ""
echo "Unit tests completed successfully!"
