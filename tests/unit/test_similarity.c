/*
 * Unit tests for cosine similarity calculation
 *
 * Tests the core similarity function used in classification.
 * This is independent of PostgreSQL and can be run standalone.
 */

#include "test_framework.h"
#include <math.h>

/* Cosine similarity function (copy from ai.c for testing) */
static float cosine_similarity(const float* a, const float* b, int dims) {
    float dot_product = 0.0f;
    for (int i = 0; i < dims; i++) {
        dot_product += a[i] * b[i];
    }
    return dot_product;
}

TEST(test_cosine_similarity_identical_vectors) {
    float v1[] = {1.0f, 0.0f, 0.0f};
    float v2[] = {1.0f, 0.0f, 0.0f};

    float similarity = cosine_similarity(v1, v2, 3);

    ASSERT_FLOAT_EQ(1.0f, similarity, 0.0001f);
}

TEST(test_cosine_similarity_orthogonal_vectors) {
    float v1[] = {1.0f, 0.0f};
    float v2[] = {0.0f, 1.0f};

    float similarity = cosine_similarity(v1, v2, 2);

    ASSERT_FLOAT_EQ(0.0f, similarity, 0.0001f);
}

TEST(test_cosine_similarity_opposite_vectors) {
    /* Note: For normalized vectors, opposite should be -1.0
     * v1 = [1, 0], v2 = [-1, 0]
     * But this assumes normalized inputs */
    float v1[] = {1.0f, 0.0f};
    float v2[] = {-1.0f, 0.0f};

    float similarity = cosine_similarity(v1, v2, 2);

    ASSERT_FLOAT_EQ(-1.0f, similarity, 0.0001f);
}

TEST(test_cosine_similarity_partial_match) {
    /* 45-degree angle between vectors
     * cos(45°) ≈ 0.707 */
    float sqrt2_inv = 1.0f / sqrtf(2.0f);
    float v1[] = {1.0f, 0.0f};
    float v2[] = {sqrt2_inv, sqrt2_inv};

    float similarity = cosine_similarity(v1, v2, 2);

    ASSERT_FLOAT_EQ(sqrt2_inv, similarity, 0.001f);
}

TEST(test_cosine_similarity_high_dimensional) {
    /* Test with realistic embedding dimensions
     * Note: cosine_similarity assumes normalized vectors (L2 norm = 1)
     * For unnormalized vectors, result is dot product, not cosine similarity */
    const int dims = 768;
    float v1[768];
    float v2[768];

    /* Initialize normalized vectors (each element = 1/sqrt(dims)) */
    float norm_value = 1.0f / sqrtf((float)dims);
    for (int i = 0; i < dims; i++) {
        v1[i] = norm_value;
        v2[i] = norm_value;
    }

    float similarity = cosine_similarity(v1, v2, dims);

    /* Identical normalized vectors should have dot product ≈ 1.0 */
    ASSERT_FLOAT_EQ(1.0f, similarity, 0.0001f);
}

TEST(test_cosine_similarity_zero_vector) {
    float v1[] = {1.0f, 2.0f, 3.0f};
    float v2[] = {0.0f, 0.0f, 0.0f};

    float similarity = cosine_similarity(v1, v2, 3);

    ASSERT_FLOAT_EQ(0.0f, similarity, 0.0001f);
}

TEST(test_cosine_similarity_single_dimension) {
    float v1[] = {1.0f};
    float v2[] = {1.0f};

    float similarity = cosine_similarity(v1, v2, 1);

    ASSERT_FLOAT_EQ(1.0f, similarity, 0.0001f);
}

int main(void) {
    printf("Testing cosine similarity function...\n\n");

    RUN_TEST(test_cosine_similarity_identical_vectors);
    RUN_TEST(test_cosine_similarity_orthogonal_vectors);
    RUN_TEST(test_cosine_similarity_opposite_vectors);
    RUN_TEST(test_cosine_similarity_partial_match);
    RUN_TEST(test_cosine_similarity_high_dimensional);
    RUN_TEST(test_cosine_similarity_zero_vector);
    RUN_TEST(test_cosine_similarity_single_dimension);

    TEST_SUMMARY();
}
