-- Test 05: Edge Cases

\set ON_ERROR_STOP on

-- Long text (500+ characters)
SELECT vector_dims(ai.embed(repeat('test ', 100))) = 384 AS long_text_works;

-- Very long text (1000+ characters)
SELECT vector_dims(ai.embed(repeat('word ', 200))) = 384 AS very_long_text_works;

-- Text with punctuation
SELECT vector_dims(ai.embed('Hello, world! How are you?')) = 384 AS punctuation_works;

-- Text with quotes
SELECT vector_dims(ai.embed('She said "hello" to me')) = 384 AS quotes_work;

-- Text with numbers
SELECT vector_dims(ai.embed('There are 123 items')) = 384 AS numbers_work;

-- Text with special characters
SELECT vector_dims(ai.embed('Price: $99.99 (20% off)')) = 384 AS special_chars_work;

-- Text with newlines
SELECT vector_dims(ai.embed(E'Line 1\nLine 2\nLine 3')) = 384 AS newlines_work;

-- Text with tabs
SELECT vector_dims(ai.embed(E'Column1\tColumn2\tColumn3')) = 384 AS tabs_work;

-- Single character
SELECT vector_dims(ai.embed('a')) = 384 AS single_char_works;

-- Unicode/UTF-8 (basic)
SELECT vector_dims(ai.embed('café résumé naïve')) = 384 AS utf8_works;
