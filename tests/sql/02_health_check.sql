-- Test 02: Health Check Function

\set ON_ERROR_STOP on

-- Returns non-NULL
SELECT ai.health_check() IS NOT NULL AS returns_non_null;

-- Returns text type
SELECT pg_typeof(ai.health_check()) = 'text'::regtype AS returns_text;

-- Contains Backend PID
SELECT ai.health_check() LIKE '%Backend PID:%' AS contains_pid;

-- Contains ONNX Runtime status
SELECT ai.health_check() LIKE '%ONNX Runtime:%' AS contains_onnx_status;

-- Contains model status
SELECT ai.health_check() LIKE '%Model loaded:%' AS contains_model_status;

-- Contains status line
SELECT ai.health_check() LIKE '%Status:%' AS contains_status;
