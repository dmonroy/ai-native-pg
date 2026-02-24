/*
 * AI Extension for PostgreSQL - Proof of Concept
 *
 * Implements IMMUTABLE ai.embed() function using ONNX Runtime
 * Model loaded once at _PG_init() into process-private memory
 *
 * Key design decisions:
 * - Single model (bge-small-en-v1.5) for PoC
 * - Lazy loading (load on first use, not at _PG_init)
 * - IMMUTABLE function (enables generated columns)
 * - CPU inference only (deterministic)
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/hsearch.h"
#include "funcapi.h"
#include "extension/vector/vector.h"
#include <onnxruntime_c_api.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

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
#define MODEL_DIMS 384
#define MAX_INPUT_LENGTH 8192
#define MAX_VOCAB_SIZE 50000
#define MAX_SEQ_LENGTH 512

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

    snprintf(vocab_path, sizeof(vocab_path), "%s/vocab.txt", models_path);

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

                        /* Copy subword */
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

    g_initialized = true;
    elog(INFO, "ai extension: ONNX Runtime initialized (models will be loaded on first use)");
}

/*
 * Extension cleanup
 */
void _PG_fini(void) {
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
 */
static void load_model(void) {
    if (g_model_loaded) {
        return;  /* Already loaded */
    }

    if (!g_initialized) {
        elog(ERROR, "ai extension: ONNX Runtime not initialized");
    }

    elog(INFO, "ai extension: Loading bge-small-en-v1.5 model (PID %d)...", getpid());

    /* Get model path from environment or use default */
    const char* models_path = getenv("AI_MODELS_PATH");
    if (!models_path) {
        models_path = "/models";
    }

    char model_path[1024];
    snprintf(model_path, sizeof(model_path), "%s/bge-small-en-v1.5.onnx", models_path);

    /* Create session options */
    OrtSessionOptions* session_options;
    OrtStatus* status = g_ort->CreateSessionOptions(&session_options);
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
    g_ort->ReleaseSessionOptions(session_options);

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
    elog(INFO, "ai extension: Model loaded successfully (~64MB, %zu inputs, %zu outputs)", num_inputs, num_outputs);

    /* Log input/output names */
    OrtAllocator* allocator;
    g_ort->GetAllocatorWithDefaultOptions(&allocator);
    for (size_t i = 0; i < num_inputs && i < 5; i++) {
        char* name;
        status = g_ort->SessionGetInputName(g_ort_session, i, allocator, &name);
        if (status == NULL) {
            elog(INFO, "  Input %zu: %s", i, name);
            allocator->Free(allocator, name);
        }
    }
    for (size_t i = 0; i < num_outputs && i < 5; i++) {
        char* name;
        status = g_ort->SessionGetOutputName(g_ort_session, i, allocator, &name);
        if (status == NULL) {
            elog(INFO, "  Output %zu: %s", i, name);
            allocator->Free(allocator, name);
        }
    }
}

/* Old simple_tokenize removed - now using wordpiece_tokenize above */

/*
 * Main embedding function
 */
PG_FUNCTION_INFO_V1(ai_embed);
Datum ai_embed(PG_FUNCTION_ARGS) {
    text* input_text;
    char* text_str;
    size_t text_len;
    OrtStatus* status;
    OrtMemoryInfo* memory_info;
    OrtValue* input_ids_tensor = NULL;
    OrtValue* attention_mask_tensor = NULL;
    OrtValue* token_type_ids_tensor = NULL;
    OrtValue* output_tensor = NULL;
    float* output_data;
    Vector* result;

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

    /* Tokenize input using BERT WordPiece tokenizer */
    int64_t token_ids[MAX_SEQ_LENGTH];
    int64_t attention_mask[MAX_SEQ_LENGTH];
    int64_t token_type_ids[MAX_SEQ_LENGTH];
    size_t token_count;
    wordpiece_tokenize(text_str, token_ids, &token_count);

    /* Create attention mask and token type IDs */
    for (size_t i = 0; i < token_count; i++) {
        attention_mask[i] = 1;
        token_type_ids[i] = 0;
    }

    /* Create ONNX tensors */
    status = g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status != NULL) {
        const char* msg = g_ort->GetErrorMessage(status);
        g_ort->ReleaseStatus(status);
        ereport(ERROR, (errmsg("Failed to create memory info: %s", msg)));
    }

    int64_t input_shape[2] = {1, (int64_t)token_count};
    size_t input_size = token_count * sizeof(int64_t);

    /* Create input_ids tensor */
    status = g_ort->CreateTensorWithDataAsOrtValue(
        memory_info, token_ids, input_size,
        input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
        &input_ids_tensor);
    if (status != NULL) {
        const char* msg = g_ort->GetErrorMessage(status);
        g_ort->ReleaseStatus(status);
        g_ort->ReleaseMemoryInfo(memory_info);
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
        g_ort->ReleaseValue(input_ids_tensor);
        g_ort->ReleaseMemoryInfo(memory_info);
        ereport(ERROR, (errmsg("Failed to create attention_mask tensor: %s", msg)));
    }

    /* Create token_type_ids tensor */
    status = g_ort->CreateTensorWithDataAsOrtValue(
        memory_info, token_type_ids, input_size,
        input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
        &token_type_ids_tensor);
    if (status != NULL) {
        const char* msg = g_ort->GetErrorMessage(status);
        g_ort->ReleaseStatus(status);
        g_ort->ReleaseValue(input_ids_tensor);
        g_ort->ReleaseValue(attention_mask_tensor);
        g_ort->ReleaseMemoryInfo(memory_info);
        ereport(ERROR, (errmsg("Failed to create token_type_ids tensor: %s", msg)));
    }

    g_ort->ReleaseMemoryInfo(memory_info);

    /* Run inference (only input_ids and attention_mask for this model) */
    const char* input_names[] = {"input_ids", "attention_mask"};
    const char* output_names[] = {"sentence_embedding"};  /* Use pre-pooled embedding */
    OrtValue* input_tensors[] = {input_ids_tensor, attention_mask_tensor};

    status = g_ort->Run(
        g_ort_session,
        NULL,  /* run options */
        input_names, (const OrtValue* const*)input_tensors, 2,
        output_names, 1,
        &output_tensor);

    g_ort->ReleaseValue(input_ids_tensor);
    g_ort->ReleaseValue(attention_mask_tensor);
    g_ort->ReleaseValue(token_type_ids_tensor);  /* Still release it */

    if (status != NULL) {
        const char* msg = g_ort->GetErrorMessage(status);
        char* error_copy = pstrdup(msg);  /* Copy before releasing */
        g_ort->ReleaseStatus(status);
        ereport(ERROR, (errmsg("Failed to run inference: %s", error_copy)));
    }

    /* Extract output tensor data */
    status = g_ort->GetTensorMutableData(output_tensor, (void**)&output_data);
    if (status != NULL) {
        const char* msg = g_ort->GetErrorMessage(status);
        g_ort->ReleaseStatus(status);
        g_ort->ReleaseValue(output_tensor);
        ereport(ERROR, (errmsg("Failed to get tensor data: %s", msg)));
    }

    /* Extract sentence embedding (already pooled and normalized by model) */
    result = create_vector(MODEL_DIMS);
    memcpy(result->x, output_data, MODEL_DIMS * sizeof(float));

    g_ort->ReleaseValue(output_tensor);

    SET_VARSIZE(result, VECTOR_SIZE(MODEL_DIMS));
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
        appendStringInfo(&buf, "Model: bge-small-en-v1.5 (384-dim)\n");
        appendStringInfo(&buf, "Status: Ready\n");
    } else {
        appendStringInfo(&buf, "Status: Model will be loaded on first ai.embed() call\n");
    }

    PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}
