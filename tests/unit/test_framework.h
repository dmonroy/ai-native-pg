#ifndef TEST_FRAMEWORK_H
#define TEST_FRAMEWORK_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* Test statistics */
extern int tests_run;
extern int tests_passed;
extern int tests_failed;

/* Color codes for output */
#define COLOR_GREEN "\033[0;32m"
#define COLOR_RED "\033[0;31m"
#define COLOR_YELLOW "\033[0;33m"
#define COLOR_RESET "\033[0m"

/* Test definition macro */
#define TEST(name) \
    static void name(void); \
    static const char* name##_test_name = #name; \
    static void name(void)

/* Run test macro */
#define RUN_TEST(name) \
    do { \
        printf("Running: %s... ", name##_test_name); \
        fflush(stdout); \
        tests_run++; \
        name(); \
        printf(COLOR_GREEN "PASSED" COLOR_RESET "\n"); \
        tests_passed++; \
    } while (0)

/* Assertion macros */
#define ASSERT_TRUE(condition) \
    do { \
        if (!(condition)) { \
            printf(COLOR_RED "FAILED" COLOR_RESET "\n"); \
            fprintf(stderr, "  Assertion failed: %s\n", #condition); \
            fprintf(stderr, "  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

#define ASSERT_FALSE(condition) \
    ASSERT_TRUE(!(condition))

#define ASSERT_EQ(expected, actual) \
    do { \
        if ((expected) != (actual)) { \
            printf(COLOR_RED "FAILED" COLOR_RESET "\n"); \
            fprintf(stderr, "  Expected: %ld\n", (long)(expected)); \
            fprintf(stderr, "  Actual:   %ld\n", (long)(actual)); \
            fprintf(stderr, "  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

#define ASSERT_STR_EQ(expected, actual) \
    do { \
        if (strcmp((expected), (actual)) != 0) { \
            printf(COLOR_RED "FAILED" COLOR_RESET "\n"); \
            fprintf(stderr, "  Expected: \"%s\"\n", (expected)); \
            fprintf(stderr, "  Actual:   \"%s\"\n", (actual)); \
            fprintf(stderr, "  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

#define ASSERT_NULL(pointer) \
    do { \
        if ((pointer) != NULL) { \
            printf(COLOR_RED "FAILED" COLOR_RESET "\n"); \
            fprintf(stderr, "  Expected NULL but got: %p\n", (void*)(pointer)); \
            fprintf(stderr, "  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

#define ASSERT_NOT_NULL(pointer) \
    do { \
        if ((pointer) == NULL) { \
            printf(COLOR_RED "FAILED" COLOR_RESET "\n"); \
            fprintf(stderr, "  Expected non-NULL pointer\n"); \
            fprintf(stderr, "  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

#define ASSERT_FLOAT_EQ(expected, actual, epsilon) \
    do { \
        double diff = fabs((double)(expected) - (double)(actual)); \
        if (diff > (epsilon)) { \
            printf(COLOR_RED "FAILED" COLOR_RESET "\n"); \
            fprintf(stderr, "  Expected: %f\n", (double)(expected)); \
            fprintf(stderr, "  Actual:   %f\n", (double)(actual)); \
            fprintf(stderr, "  Diff:     %f (epsilon: %f)\n", diff, (double)(epsilon)); \
            fprintf(stderr, "  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

/* Test summary */
#define TEST_SUMMARY() \
    do { \
        printf("\n" COLOR_YELLOW "================================\n"); \
        printf("        Test Summary\n"); \
        printf("================================" COLOR_RESET "\n"); \
        printf("Total:  %d\n", tests_run); \
        printf(COLOR_GREEN "Passed: %d" COLOR_RESET "\n", tests_passed); \
        if (tests_failed > 0) { \
            printf(COLOR_RED "Failed: %d" COLOR_RESET "\n", tests_failed); \
        } else { \
            printf("Failed: 0\n"); \
        } \
        printf("\n"); \
        if (tests_failed == 0) { \
            printf(COLOR_GREEN "✓ All tests passed!" COLOR_RESET "\n"); \
            return 0; \
        } else { \
            printf(COLOR_RED "✗ Some tests failed" COLOR_RESET "\n"); \
            return 1; \
        } \
    } while (0)

#endif /* TEST_FRAMEWORK_H */
