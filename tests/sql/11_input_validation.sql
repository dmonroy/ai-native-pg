-- Test 11: Input Validation

\set ON_ERROR_STOP on

-- Valid UTF-8 text works
SELECT vector_dims(ai.embed('Valid UTF-8: café, résumé, naïve')) = 384
       AS valid_utf8_works;

-- Text with accents
SELECT vector_dims(ai.embed('Héllo Wörld')) = 384
       AS accented_text_works;

-- Text with emoji (if supported)
SELECT vector_dims(ai.embed('Hello 👋 World')) = 384
       AS emoji_text_works;

-- Very long single word (tests buffer handling)
SELECT vector_dims(ai.embed(repeat('a', 200))) = 384
       AS long_word_works;

-- Maximum reasonable input length
SELECT vector_dims(ai.embed(repeat('test ', 1000))) = 384
       AS max_input_works;

-- Mixed languages
SELECT vector_dims(ai.embed('Hello Bonjour Hola')) = 384
       AS mixed_language_works;
