/*
 * AI Extension for PostgreSQL - Proof of Concept
 *
 * Implements IMMUTABLE ai.embed() function using ONNX Runtime
 * Model loaded once at _PG_init() into process-private memory
 *
 * Key design decisions:
 * - Single model (nomic-embed-text-v1.5) for PoC
 * - Lazy loading (load on first use, not at _PG_init)
 * - IMMUTABLE function (enables generated columns)
 * - CPU inference only (deterministic)
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/hsearch.h"
#include "utils/guc.h"
#include "access/hash.h"
#include "funcapi.h"
#include "mb/pg_wchar.h"
#include "extension/vector/vector.h"
#include <onnxruntime_c_api.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <sys/stat.h>
#include <errno.h>

PG_MODULE_MAGIC;

/*
 * Global state (per backend process)
 */
static const OrtApi* g_ort = NULL;
static OrtEnv* g_ort_env = NULL;
static OrtSession* g_ort_session = NULL;
static bool g_initialized = false;
static bool g_model_loaded = false;

/* Model configuration */
#define MODEL_DIMS 768
#define MAX_INPUT_LENGTH 8192
#define MAX_VOCAB_SIZE 50000
#define MAX_SEQ_LENGTH 8192

/* Vocabulary hash table entry */
typedef struct {
    char token[256];    /* Token string - must be first field for hash key */
    int token_id;       /* Token ID value */
} VocabEntry;

/* Global vocabulary state */
static HTAB* g_vocab_hash = NULL;
static int g_vocab_size = 0;
static bool g_vocab_loaded = false;

/* Special token IDs */
#define TOKEN_PAD 0
#define TOKEN_UNK 100
#define TOKEN_CLS 101
#define TOKEN_SEP 102
#define TOKEN_MASK 103

/*
 * Category Embedding Cache
 *
 * Critical performance optimization for ai.classify():
 * - Without cache: 5 categories × 5ms = 25ms per classification (95% wasted)
 * - With cache: 5 categories × 0.01ms = 0.05ms per classification
 *
 * Memory layout per entry: ~3.3KB
 * - category_text: 256 bytes (max category name length)
 * - embedding: 768 floats × 4 bytes = 3,072 bytes
 * - HTAB overhead: ~100 bytes
 * Total: ~3,428 bytes ≈ 3.4KB per entry (design called for ~2KB but this is more realistic)
 */
typedef struct {
    char category_text[256];    /* Category string - must be first field for hash key */
    float embedding[MODEL_DIMS]; /* Precomputed embedding vector (768 dims) */
} CategoryCacheEntry;

/* Global category cache state (per backend process) */
static HTAB* g_category_cache = NULL;
static bool g_category_cache_initialized = false;

/* Cache statistics for monitoring */
static int64 g_cache_hits = 0;
static int64 g_cache_misses = 0;

/* GUC variables */
static int ai_max_cached_categories = 10000; /* Default: 10K categories (~34MB) */

/* Forward declarations */
Datum ai_embed(PG_FUNCTION_ARGS);

/*
 * Initialize a Vector (pgvector helper)
 * Equivalent to pgvector's InitVector() function
 */
static Vector* create_vector(int dim) {
    Vector* result;
    int size = VECTOR_SIZE(dim);

    result = (Vector*)palloc0(size);
    SET_VARSIZE(result, size);
    result->dim = dim;
    result->unused = 0;

    return result;
}

/*
 * Load BERT vocabulary from vocab.txt into hash table
 * Uses PostgreSQL's HTAB for O(1) lookup performance
 */
static void load_vocabulary(void) {
    FILE* fp = NULL;
    char line[256];
    int token_id = 0;
    const char* models_path;
    char vocab_path[1024];
    HASHCTL hash_ctl;

    if (g_vocab_loaded) {
        return;
    }

    models_path = getenv("AI_MODELS_PATH");
    if (!models_path) {
        models_path = "/models";
    }

    snprintf(vocab_path, sizeof(vocab_path), "%s/nomic-embed-text-v1.5/vocab.txt", models_path);

    /* Validate vocabulary path for security (improvement #12) */
    if (strstr(vocab_path, "..") != NULL) {
        elog(ERROR, "ai extension: Path traversal attempt blocked: %s", vocab_path);
        return;
    }

    /* Check file exists and is readable */
    if (access(vocab_path, R_OK) != 0) {
        int saved_errno = errno;
        elog(ERROR, "ai extension: Cannot access vocabulary file: %s (error %d)",
             vocab_path, saved_errno);
        return;
    }

    /* Open file FIRST, before allocating hash table */
    fp = fopen(vocab_path, "r");
    if (!fp) {
        elog(ERROR, "Failed to open vocabulary file: %s", vocab_path);
        return;
    }

    /* Initialize hash table for O(1) token lookup */
    memset(&hash_ctl, 0, sizeof(hash_ctl));
    hash_ctl.keysize = 256;  /* Max token length */
    hash_ctl.entrysize = sizeof(VocabEntry);
    /* Use default string hash function */

    g_vocab_hash = hash_create("vocab_hash",
                                MAX_VOCAB_SIZE,  /* Initial size */
                                &hash_ctl,
                                HASH_ELEM | HASH_STRINGS);

    if (!g_vocab_hash) {
        fclose(fp);
        elog(ERROR, "Failed to create vocabulary hash table");
        return;
    }

    /* Use PG_TRY for cleanup on error */
    PG_TRY();
    {
        /* Read vocabulary file and populate hash table */
        while (fgets(line, sizeof(line), fp) && token_id < MAX_VOCAB_SIZE) {
            VocabEntry* entry;
            bool found;
            size_t len = strlen(line);

            /* Remove newline */
            if (len > 0 && line[len-1] == '\n') {
                line[len-1] = '\0';
                len--;
            }

            /* Validate token */
            if (len == 0) {
                elog(WARNING, "Empty token at line %d, skipping", token_id + 1);
                continue;
            }

            if (len >= 256) {
                elog(WARNING, "Token too long at line %d (len=%zu), truncating",
                     token_id + 1, len);
                line[255] = '\0';
                len = 255;
            }

            /* Check for control characters (improvement #12) */
            bool has_control_chars = false;
            for (size_t i = 0; i < len; i++) {
                if ((unsigned char)line[i] < 32 && line[i] != '\t') {
                    elog(WARNING, "Control character in token at line %d, skipping", token_id + 1);
                    has_control_chars = true;
                    break;
                }
            }
            if (has_control_chars) {
                continue;
            }

            /* Insert into hash table */
            entry = (VocabEntry*)hash_search(g_vocab_hash, line, HASH_ENTER, &found);
            if (!found) {
                /* New entry - set token_id */
                entry->token_id = token_id;
                token_id++;
            } else {
                elog(WARNING, "Duplicate token at line %d: %s", token_id + 1, line);
            }
        }

        fclose(fp);
        fp = NULL;

        g_vocab_size = token_id;
        g_vocab_loaded = true;

        elog(INFO, "ai extension: Loaded vocabulary with %d tokens into hash table (O(1) lookup)",
             g_vocab_size);
    }
    PG_CATCH();
    {
        /* Clean up on error */
        if (fp) {
            fclose(fp);
        }
        if (g_vocab_hash) {
            hash_destroy(g_vocab_hash);
            g_vocab_hash = NULL;
        }
        g_vocab_loaded = false;
        PG_RE_THROW();
    }
    PG_END_TRY();
}

/*
 * Find token ID in vocabulary using hash table (O(1) lookup)
 * Replaces previous O(n) linear search implementation
 */
static int find_token_id(const char* token) {
    VocabEntry* entry;
    bool found;

    if (!g_vocab_hash) {
        return TOKEN_UNK;
    }

    /* Hash table lookup - O(1) average case */
    entry = (VocabEntry*)hash_search(g_vocab_hash, token, HASH_FIND, &found);

    if (found) {
        return entry->token_id;
    }

    return TOKEN_UNK;
}

/*
 * Convert character to lowercase
 */
static char to_lower(char c) {
    if (c >= 'A' && c <= 'Z') {
        return c + ('a' - 'A');
    }
    return c;
}

/*
 * Check if character is punctuation
 */
static bool is_punctuation(char c) {
    return (c == '!' || c == '?' || c == '.' || c == ',' ||
            c == ';' || c == ':' || c == '-' || c == '\'' ||
            c == '"' || c == '(' || c == ')');
}

/*
 * BERT WordPiece tokenizer
 * Implements greedy longest-match-first algorithm
 */
static void wordpiece_tokenize(const char* text, int64_t* token_ids, size_t* token_count) {
    char word[256];
    char subword[256];
    int pos = 0;
    int word_pos = 0;
    size_t output_pos = 0;
    const char* p = text;
    bool word_truncated = false;  /* Track if any word was truncated */

    if (!g_vocab_loaded) {
        load_vocabulary();
    }

    /* Add [CLS] token */
    token_ids[output_pos++] = TOKEN_CLS;

    /* Process input text */
    while (*p && output_pos < MAX_SEQ_LENGTH - 1) {
        char c = *p;

        /* Handle whitespace - tokenize current word */
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            if (word_pos > 0) {
                word[word_pos] = '\0';

                /* WordPiece tokenization for this word */
                int w_start = 0;
                bool is_first_subword = true;

                while (w_start < word_pos && output_pos < MAX_SEQ_LENGTH - 1) {
                    int w_end = word_pos;
                    int found_id = TOKEN_UNK;

                    /* Greedy longest-match-first */
                    while (w_start < w_end) {
                        int subword_len = w_end - w_start;
                        int prefix_len = 0;

                        /* Add ## prefix for non-first subwords */
                        if (!is_first_subword) {
                            subword[0] = '#';
                            subword[1] = '#';
                            prefix_len = 2;
                        }

                        /* Copy subword with bounds checking */
                        int total_len = prefix_len + subword_len;
                        if (total_len >= 255) {
                            /* Subword too long - truncate to fit buffer */
                            subword_len = 255 - prefix_len - 1;
                            if (!word_truncated) {
                                word_truncated = true;
                                elog(WARNING, "ai extension: Subword exceeds buffer size and was truncated");
                            }
                        }
                        memcpy(subword + prefix_len, word + w_start, subword_len);
                        subword[prefix_len + subword_len] = '\0';

                        /* Look up in vocabulary */
                        found_id = find_token_id(subword);
                        if (found_id != TOKEN_UNK) {
                            break;
                        }
                        w_end--;
                    }

                    if (w_end == w_start) {
                        /* No match found, use [UNK] */
                        token_ids[output_pos++] = TOKEN_UNK;
                        break;
                    } else {
                        token_ids[output_pos++] = found_id;
                        w_start = w_end;
                        is_first_subword = false;
                    }
                }

                word_pos = 0;
            }
            p++;
            continue;
        }

        /* Handle punctuation as separate tokens */
        if (is_punctuation(c)) {
            /* Tokenize pending word first */
            if (word_pos > 0) {
                word[word_pos] = '\0';
                int token_id = find_token_id(word);
                token_ids[output_pos++] = token_id;
                word_pos = 0;
            }

            /* Tokenize punctuation */
            char punct[2] = {c, '\0'};
            int token_id = find_token_id(punct);
            token_ids[output_pos++] = token_id;
            p++;
            continue;
        }

        /* Accumulate word characters (lowercase) */
        if (word_pos < 255) {
            word[word_pos++] = to_lower(c);
        } else {
            /* Buffer full - silently skip remaining characters of this word */
            /* Mark truncation for warning after tokenization completes */
            if (!word_truncated) {
                word_truncated = true;
                elog(WARNING, "ai extension: Word exceeds 255 characters and was truncated during tokenization");
            }
        }
        p++;
    }

    /* Process final word */
    if (word_pos > 0 && output_pos < MAX_SEQ_LENGTH - 1) {
        word[word_pos] = '\0';
        int token_id = find_token_id(word);
        token_ids[output_pos++] = token_id;
    }

    /* Add [SEP] token */
    token_ids[output_pos++] = TOKEN_SEP;

    *token_count = output_pos;
}

/*
 * Initialize category embedding cache
 * Lazy initialization on first use
 */
static void init_category_cache(void) {
    HASHCTL hash_ctl;

    if (g_category_cache_initialized) {
        return;
    }

    /* Configure hash table */
    MemSet(&hash_ctl, 0, sizeof(hash_ctl));
    hash_ctl.keysize = 256;  /* Size of category_text field */
    hash_ctl.entrysize = sizeof(CategoryCacheEntry);
    hash_ctl.hash = string_hash;  /* Use PostgreSQL's string hash function */

    /* Create hash table with initial size for 1024 entries */
    g_category_cache = hash_create("AI Category Embedding Cache",
                                   1024,
                                   &hash_ctl,
                                   HASH_ELEM | HASH_FUNCTION);

    g_category_cache_initialized = true;
    elog(DEBUG1, "ai extension: Category cache initialized (max entries: %d)",
         ai_max_cached_categories);
}

/*
 * Get or compute category embedding
 * Returns pointer to cached embedding (do not free!)
 *
 * This is the core cache function that provides 10-100× speedup:
 * - Cache hit: ~0.01ms (hash lookup)
 * - Cache miss: ~5ms (embedding computation + cache storage)
 */
static float* get_category_embedding(const char* category_text) {
    CategoryCacheEntry* entry;
    bool found;
    char key[256];
    Vector* embedding_vec;
    text* category_text_pg;

    /* Initialize cache on first use */
    init_category_cache();

    /* Check cache size limit */
    if (hash_get_num_entries(g_category_cache) >= ai_max_cached_categories) {
        elog(WARNING, "ai extension: Category cache full (%d entries), cache miss will still work but may be slow",
             ai_max_cached_categories);
    }

    /* Prepare key (truncate if needed) */
    strncpy(key, category_text, sizeof(key) - 1);
    key[sizeof(key) - 1] = '\0';

    /* Look up in cache */
    entry = (CategoryCacheEntry*) hash_search(g_category_cache,
                                               key,
                                               HASH_FIND,
                                               &found);

    if (found) {
        /* Cache hit! */
        g_cache_hits++;
        elog(DEBUG2, "ai extension: Category cache HIT for '%s' (hits: %lld, misses: %lld)",
             category_text, (long long)g_cache_hits, (long long)g_cache_misses);
        return entry->embedding;
    }

    /* Cache miss - compute embedding */
    g_cache_misses++;
    elog(DEBUG2, "ai extension: Category cache MISS for '%s' (hits: %lld, misses: %lld)",
         category_text, (long long)g_cache_hits, (long long)g_cache_misses);

    /* Convert category text to PostgreSQL text type for ai_embed */
    category_text_pg = cstring_to_text(category_text);

    /* Compute embedding using ai_embed - note: this is called from within the same transaction */
    embedding_vec = DatumGetVector(DirectFunctionCall1(ai_embed, PointerGetDatum(category_text_pg)));

    /* Verify dimensions */
    if (embedding_vec->dim != MODEL_DIMS) {
        elog(ERROR, "ai extension: Category embedding dimension mismatch: expected %d, got %d",
             MODEL_DIMS, embedding_vec->dim);
    }

    /* Store in cache (HASH_ENTER will create new entry if not at max size) */
    if (hash_get_num_entries(g_category_cache) < ai_max_cached_categories) {
        entry = (CategoryCacheEntry*) hash_search(g_category_cache,
                                                   key,
                                                   HASH_ENTER,
                                                   &found);
        if (entry) {
            /* Copy embedding data */
            memcpy(entry->embedding, embedding_vec->x, MODEL_DIMS * sizeof(float));
            /* Hash value is computed internally by HTAB */

            elog(DEBUG1, "ai extension: Cached embedding for category '%s' (total entries: %ld)",
                 category_text, hash_get_num_entries(g_category_cache));
        }
    } else {
        elog(DEBUG1, "ai extension: Cache full, not caching category '%s'", category_text);
        /* Even if cache is full, we still computed the embedding - need to handle this */
        /* For now, we'll just return it without caching - caller must copy if needed */
        return embedding_vec->x;
    }

    return entry->embedding;
}

/*
 * Extension initialization
 * Called once per backend process when extension is loaded
 */
void _PG_init(void) {
    elog(INFO, "ai extension: Initializing (PID %d)", getpid());

    /* Initialize ONNX Runtime API */
    g_ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (!g_ort) {
        elog(ERROR, "ai extension: Failed to get ONNX Runtime API");
        return;
    }

    /* Create ONNX Runtime environment */
    OrtStatus* status = g_ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "ai", &g_ort_env);
    if (status != NULL) {
        const char* msg = g_ort->GetErrorMessage(status);
        g_ort->ReleaseStatus(status);
        elog(ERROR, "ai extension: Failed to create ONNX environment: %s", msg);
        return;
    }

    /* Register GUCs (Grand Unified Configuration) */
    DefineCustomIntVariable("ai.max_cached_categories",
                            "Maximum number of category embeddings to cache",
                            "Category embeddings are cached to speed up classification. "
                            "Default is 10000 categories (~34MB). Min 100, Max 100000.",
                            &ai_max_cached_categories,
                            10000,  /* default */
                            100,    /* min */
                            100000, /* max */
                            PGC_USERSET,
                            0,
                            NULL, NULL, NULL);

    g_initialized = true;
    elog(INFO, "ai extension: ONNX Runtime initialized (models will be loaded on first use)");
    elog(DEBUG1, "ai extension: GUC ai.max_cached_categories = %d", ai_max_cached_categories);
}

/*
 * Extension cleanup
 */
void _PG_fini(void) {
    /* Log cache statistics before cleanup */
    if (g_category_cache_initialized && g_category_cache) {
        elog(DEBUG1, "ai extension: Category cache stats - hits: %lld, misses: %lld, entries: %ld, hit_ratio: %.2f%%",
             (long long)g_cache_hits,
             (long long)g_cache_misses,
             hash_get_num_entries(g_category_cache),
             (g_cache_hits + g_cache_misses) > 0 ?
                 100.0 * g_cache_hits / (g_cache_hits + g_cache_misses) : 0.0);
    }

    /* Clean up category cache */
    if (g_category_cache) {
        hash_destroy(g_category_cache);
        g_category_cache = NULL;
        g_category_cache_initialized = false;
    }

    /* Clean up vocabulary hash table */
    if (g_vocab_hash) {
        hash_destroy(g_vocab_hash);
        g_vocab_hash = NULL;
        g_vocab_loaded = false;
    }

    /* Clean up ONNX Runtime resources */
    if (g_ort_session) {
        g_ort->ReleaseSession(g_ort_session);
        g_ort_session = NULL;
    }

    if (g_ort_env) {
        g_ort->ReleaseEnv(g_ort_env);
        g_ort_env = NULL;
    }

    elog(INFO, "ai extension: Cleaned up (PID %d)", getpid());
}

/*
 * Load ONNX model (lazy loading)
 * Called on first use of ai.embed()
 * Uses PG_TRY/CATCH for proper resource cleanup on errors
 */
static void load_model(void) {
    OrtSessionOptions* session_options = NULL;
    OrtStatus* status;
    const char* models_path;
    char model_path[1024];

    if (g_model_loaded) {
        return;  /* Already loaded */
    }

    if (!g_initialized) {
        elog(ERROR, "ai extension: ONNX Runtime not initialized");
    }

    elog(INFO, "ai extension: Loading nomic-embed-text-v1.5 model (PID %d)...", getpid());

    /* Get model path from environment or use default */
    models_path = getenv("AI_MODELS_PATH");
    if (!models_path) {
        models_path = "/models";
    }

    snprintf(model_path, sizeof(model_path), "%s/nomic-embed-text-v1.5/model_int8.onnx", models_path);

    /* Validate model path for security (improvement #12) */
    if (strstr(model_path, "..") != NULL) {
        elog(ERROR, "ai extension: Path traversal attempt blocked: %s", model_path);
    }

    if (model_path[0] != '/') {
        elog(ERROR, "ai extension: Model path must be absolute: %s", model_path);
    }

    /* Check file exists and is readable */
    if (access(model_path, R_OK) != 0) {
        int saved_errno = errno;
        elog(ERROR, "ai extension: Cannot access model file: %s (error %d)",
             model_path, saved_errno);
    }

    /* Check file size (should be ~137MB for nomic-embed INT8) */
    struct stat st;
    if (stat(model_path, &st) == 0) {
        if (st.st_size < 1024 * 1024) {
            elog(WARNING, "ai extension: Model file seems too small: %ld bytes", (long)st.st_size);
        }
        if (st.st_size > 500 * 1024 * 1024) {
            elog(WARNING, "ai extension: Model file seems too large: %ld bytes", (long)st.st_size);
        }
    }

    /* Use PG_TRY for proper cleanup on error */
    PG_TRY();
    {
        /* Create session options */
        status = g_ort->CreateSessionOptions(&session_options);
        if (status != NULL) {
            const char* msg = g_ort->GetErrorMessage(status);
            g_ort->ReleaseStatus(status);
            elog(ERROR, "ai extension: Failed to create session options: %s", msg);
        }

        /* Set session options for deterministic CPU inference */
        status = g_ort->SetIntraOpNumThreads(session_options, 1);
        if (status != NULL) {
            g_ort->ReleaseStatus(status);
            /* Non-fatal, continue */
        }

        status = g_ort->SetSessionGraphOptimizationLevel(session_options, ORT_ENABLE_ALL);
        if (status != NULL) {
            g_ort->ReleaseStatus(status);
            /* Non-fatal, continue */
        }

        /* Load model */
        status = g_ort->CreateSession(g_ort_env, model_path, session_options, &g_ort_session);

        /* Release session options (success or failure) */
        if (session_options) {
            g_ort->ReleaseSessionOptions(session_options);
            session_options = NULL;
        }

        if (status != NULL) {
            const char* msg = g_ort->GetErrorMessage(status);
            g_ort->ReleaseStatus(status);
            elog(ERROR, "ai extension: Failed to load model from %s: %s", model_path, msg);
        }

        g_model_loaded = true;

        /* Log model input/output info for debugging */
        size_t num_inputs = 0, num_outputs = 0;
        g_ort->SessionGetInputCount(g_ort_session, &num_inputs);
        g_ort->SessionGetOutputCount(g_ort_session, &num_outputs);
        elog(INFO, "ai extension: Model loaded successfully (~137MB INT8, %zu inputs, %zu outputs)", num_inputs, num_outputs);

        /* Log input/output names */
        OrtAllocator* allocator;
        g_ort->GetAllocatorWithDefaultOptions(&allocator);
        elog(INFO, "ai extension: === Model Input/Output Info ===");
        for (size_t i = 0; i < num_inputs && i < 5; i++) {
            char* name;
            status = g_ort->SessionGetInputName(g_ort_session, i, allocator, &name);
            if (status == NULL) {
                elog(INFO, "ai extension:   Input %zu: %s", i, name);
                allocator->Free(allocator, name);
            }
        }
        for (size_t i = 0; i < num_outputs && i < 5; i++) {
            char* name;
            status = g_ort->SessionGetOutputName(g_ort_session, i, allocator, &name);
            if (status == NULL) {
                elog(INFO, "ai extension:   Output %zu: %s", i, name);
                allocator->Free(allocator, name);
            }
        }
    }
    PG_CATCH();
    {
        /* Clean up on error */
        if (session_options) {
            g_ort->ReleaseSessionOptions(session_options);
        }
        if (g_ort_session) {
            g_ort->ReleaseSession(g_ort_session);
            g_ort_session = NULL;
        }
        g_model_loaded = false;
        PG_RE_THROW();
    }
    PG_END_TRY();
}

/* Old simple_tokenize removed - now using wordpiece_tokenize above */

/*
 * Main embedding function
 * Uses PG_TRY/CATCH for comprehensive resource cleanup
 * Addresses improvement #3: prevents ONNX tensor leaks on errors
 * Also fixes improvement #5: moves arrays from stack to heap
 */
PG_FUNCTION_INFO_V1(ai_embed);
Datum ai_embed(PG_FUNCTION_ARGS) {
    text* input_text;
    char* text_str;
    size_t text_len;
    OrtStatus* status = NULL;
    OrtMemoryInfo* memory_info = NULL;
    OrtValue* input_ids_tensor = NULL;
    OrtValue* attention_mask_tensor = NULL;
    OrtValue* token_type_ids_tensor = NULL;
    OrtValue* output_tensor = NULL;
    float* output_data;
    Vector* result = NULL;
    int64_t* token_ids = NULL;
    int64_t* attention_mask = NULL;
    int64_t* token_type_ids = NULL;
    size_t token_count;
    int64_t input_shape[2];
    size_t input_size;

    /* Check for NULL input */
    if (PG_ARGISNULL(0)) {
        PG_RETURN_NULL();
    }

    /* Lazy load model on first use */
    if (!g_model_loaded) {
        load_model();
    }

    /* Get input text */
    input_text = PG_GETARG_TEXT_PP(0);
    text_len = VARSIZE_ANY_EXHDR(input_text);

    /* Validate input length */
    if (text_len > MAX_INPUT_LENGTH) {
        ereport(ERROR,
            (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
             errmsg("Input text too long (%zu bytes, max %d)", text_len, MAX_INPUT_LENGTH),
             errhint("Consider chunking your text into smaller segments")));
    }

    if (text_len == 0) {
        ereport(ERROR,
            (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
             errmsg("Cannot embed empty string")));
    }

    /* Convert to C string */
    text_str = text_to_cstring(input_text);

    /* Validate UTF-8 encoding (improvement #12) */
    if (!pg_verify_mbstr(PG_UTF8, text_str, text_len, false)) {
        ereport(ERROR,
            (errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE),
             errmsg("Invalid UTF-8 sequence in input text"),
             errhint("Ensure input text is valid UTF-8 encoding")));
    }

    /* Check for null bytes (invalid in text) */
    if (strlen(text_str) != text_len) {
        ereport(ERROR,
            (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
             errmsg("Input text contains null bytes"),
             errhint("Remove null bytes from input text")));
    }

    /* Allocate arrays on heap to avoid stack overflow (improvement #5) */
    token_ids = (int64_t*)palloc(MAX_SEQ_LENGTH * sizeof(int64_t));
    attention_mask = (int64_t*)palloc(MAX_SEQ_LENGTH * sizeof(int64_t));

    /* Use PG_TRY for comprehensive cleanup on errors */
    PG_TRY();
    {
        /* Tokenize input using BERT WordPiece tokenizer */
        wordpiece_tokenize(text_str, token_ids, &token_count);

        /* Create attention mask */
        for (size_t i = 0; i < token_count; i++) {
            attention_mask[i] = 1;
        }

        /* Create ONNX tensors */
        status = g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
        if (status != NULL) {
            const char* msg = g_ort->GetErrorMessage(status);
            g_ort->ReleaseStatus(status);
            ereport(ERROR, (errmsg("Failed to create memory info: %s", msg)));
        }

        input_shape[0] = 1;
        input_shape[1] = (int64_t)token_count;
        input_size = token_count * sizeof(int64_t);

        /* Create input_ids tensor */
        status = g_ort->CreateTensorWithDataAsOrtValue(
            memory_info, token_ids, input_size,
            input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
            &input_ids_tensor);
        if (status != NULL) {
            const char* msg = g_ort->GetErrorMessage(status);
            g_ort->ReleaseStatus(status);
            ereport(ERROR, (errmsg("Failed to create input_ids tensor: %s", msg)));
        }

        /* Create attention_mask tensor */
        status = g_ort->CreateTensorWithDataAsOrtValue(
            memory_info, attention_mask, input_size,
            input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
            &attention_mask_tensor);
        if (status != NULL) {
            const char* msg = g_ort->GetErrorMessage(status);
            g_ort->ReleaseStatus(status);
            ereport(ERROR, (errmsg("Failed to create attention_mask tensor: %s", msg)));
        }

        /* Create token_type_ids tensor (all zeros for single sentence) */
        token_type_ids = (int64_t*)palloc(MAX_SEQ_LENGTH * sizeof(int64_t));
        memset(token_type_ids, 0, token_count * sizeof(int64_t));

        status = g_ort->CreateTensorWithDataAsOrtValue(
            memory_info, token_type_ids, input_size,
            input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
            &token_type_ids_tensor);
        if (status != NULL) {
            const char* msg = g_ort->GetErrorMessage(status);
            g_ort->ReleaseStatus(status);
            ereport(ERROR, (errmsg("Failed to create token_type_ids tensor: %s", msg)));
        }

        /* Release memory_info after all tensors created */
        g_ort->ReleaseMemoryInfo(memory_info);
        memory_info = NULL;

        /* Run inference (3 inputs for nomic-embed) */
        const char* input_names[] = {"input_ids", "token_type_ids", "attention_mask"};
        const char* output_names[] = {"last_hidden_state"};
        OrtValue* input_tensors[] = {input_ids_tensor, token_type_ids_tensor, attention_mask_tensor};

        status = g_ort->Run(
            g_ort_session,
            NULL,  /* run options */
            input_names, (const OrtValue* const*)input_tensors, 3,
            output_names, 1,
            &output_tensor);

        if (status != NULL) {
            const char* msg = g_ort->GetErrorMessage(status);
            char* error_copy = pstrdup(msg);
            g_ort->ReleaseStatus(status);
            ereport(ERROR, (errmsg("Failed to run inference: %s", error_copy)));
        }

        /* Extract output tensor data */
        status = g_ort->GetTensorMutableData(output_tensor, (void**)&output_data);
        if (status != NULL) {
            const char* msg = g_ort->GetErrorMessage(status);
            g_ort->ReleaseStatus(status);
            ereport(ERROR, (errmsg("Failed to get tensor data: %s", msg)));
        }

        /* Mean pooling: average token embeddings weighted by attention mask
         * Output shape: [1, token_count, 768]
         * Need to pool across sequence dimension to get [1, 768]
         */
        float pooled[MODEL_DIMS];
        memset(pooled, 0, MODEL_DIMS * sizeof(float));

        int mask_sum = 0;
        for (size_t i = 0; i < token_count; i++) {
            if (attention_mask[i] == 1) {
                mask_sum++;
                for (int j = 0; j < MODEL_DIMS; j++) {
                    pooled[j] += output_data[i * MODEL_DIMS + j];
                }
            }
        }

        /* Average by mask sum */
        for (int j = 0; j < MODEL_DIMS; j++) {
            pooled[j] /= (float)mask_sum;
        }

        /* L2 normalization */
        float norm = 0.0f;
        for (int j = 0; j < MODEL_DIMS; j++) {
            norm += pooled[j] * pooled[j];
        }
        norm = sqrtf(norm);

        result = create_vector(MODEL_DIMS);
        for (int j = 0; j < MODEL_DIMS; j++) {
            result->x[j] = pooled[j] / norm;
        }
        SET_VARSIZE(result, VECTOR_SIZE(MODEL_DIMS));
    }
    PG_FINALLY();
    {
        /* Always clean up resources, success or failure */
        if (output_tensor) {
            g_ort->ReleaseValue(output_tensor);
        }
        if (attention_mask_tensor) {
            g_ort->ReleaseValue(attention_mask_tensor);
        }
        if (token_type_ids_tensor) {
            g_ort->ReleaseValue(token_type_ids_tensor);
        }
        if (input_ids_tensor) {
            g_ort->ReleaseValue(input_ids_tensor);
        }
        if (memory_info) {
            g_ort->ReleaseMemoryInfo(memory_info);
        }
        if (token_ids) {
            pfree(token_ids);
        }
        if (attention_mask) {
            pfree(attention_mask);
        }
        if (token_type_ids) {
            pfree(token_type_ids);
        }
    }
    PG_END_TRY();

    PG_RETURN_VECTOR_P(result);
}

/*
 * Health check function
 */
PG_FUNCTION_INFO_V1(ai_health_check);
Datum ai_health_check(PG_FUNCTION_ARGS) {
    StringInfoData buf;
    initStringInfo(&buf);

    appendStringInfo(&buf, "AI Extension Health Check\n");
    appendStringInfo(&buf, "Backend PID: %d\n", getpid());
    appendStringInfo(&buf, "ONNX Runtime: %s\n", g_initialized ? "initialized" : "NOT initialized");
    appendStringInfo(&buf, "Model loaded: %s\n", g_model_loaded ? "YES" : "NO");

    if (g_model_loaded) {
        appendStringInfo(&buf, "Model: nomic-embed-text-v1.5 (768-dim, INT8)\n");
        appendStringInfo(&buf, "Status: Ready\n");
    } else {
        appendStringInfo(&buf, "Status: Model will be loaded on first ai.embed() call\n");
    }

    PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/*
 * ai.classify_cache_stats()
 *
 * Returns cache statistics for monitoring performance
 * Returns: table(hits bigint, misses bigint, entries bigint, memory_mb numeric)
 */
PG_FUNCTION_INFO_V1(ai_classify_cache_stats);
Datum ai_classify_cache_stats(PG_FUNCTION_ARGS) {
    TupleDesc tupdesc;
    Datum values[4];
    bool nulls[4];
    HeapTuple tuple;
    int64 num_entries = 0;
    double memory_mb = 0.0;

    /* Build tuple descriptor */
    if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE) {
        ereport(ERROR,
                (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                 errmsg("function returning record called in context that cannot accept type record")));
    }

    /* Get cache statistics */
    if (g_category_cache_initialized && g_category_cache) {
        num_entries = hash_get_num_entries(g_category_cache);
        /* Memory calculation: ~3.4KB per entry (256B text + 3KB embedding + overhead) */
        memory_mb = (num_entries * 3.4) / 1024.0;
    }

    /* Build result tuple */
    MemSet(nulls, 0, sizeof(nulls));
    values[0] = Int64GetDatum(g_cache_hits);
    values[1] = Int64GetDatum(g_cache_misses);
    values[2] = Int64GetDatum(num_entries);
    values[3] = Float8GetDatum(memory_mb);

    tuple = heap_form_tuple(tupdesc, values, nulls);
    PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}

