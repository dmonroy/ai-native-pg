# Makefile for AI extension unit tests

CC = gcc
CFLAGS = -Wall -Wextra -g -O0 -std=c11
LDFLAGS = -lm

# Test framework
FRAMEWORK_OBJS = test_framework.o

# Test binaries
TESTS = test_similarity

# Default target: build all tests
all: $(TESTS)

# Build test framework object
test_framework.o: test_framework.c test_framework.h
	$(CC) $(CFLAGS) -c test_framework.c -o test_framework.o

# Build similarity tests
test_similarity: test_similarity.c $(FRAMEWORK_OBJS)
	$(CC) $(CFLAGS) test_similarity.c $(FRAMEWORK_OBJS) $(LDFLAGS) -o test_similarity

# Run all tests
test: $(TESTS)
	@echo "Running unit tests..."
	@for test in $(TESTS); do \
		echo ""; \
		./$$test || exit 1; \
	done

# Clean build artifacts
clean:
	rm -f $(TESTS) *.o

# Run with valgrind for memory leak detection
valgrind: $(TESTS)
	@for test in $(TESTS); do \
		echo "Running $$test with valgrind..."; \
		valgrind --leak-check=full --show-leak-kinds=all \
			--track-origins=yes --error-exitcode=1 \
			./$$test || exit 1; \
	done

# Code coverage (requires gcov)
coverage: CFLAGS += --coverage
coverage: clean $(TESTS)
	@for test in $(TESTS); do \
		./$$test; \
	done
	@gcov *.c
	@echo "Coverage reports generated: *.gcov"

.PHONY: all test clean valgrind coverage
