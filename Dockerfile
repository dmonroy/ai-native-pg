# AI-Native Postgres - Proof of Concept
# Multistage build for cleaner image

# ============================================================================
# Stage 1: Builder
# ============================================================================
FROM postgres:16 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-16 \
    postgresql-16-pgvector \
    wget \
    cmake \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install ONNX Runtime (detect architecture)
RUN ARCH=$(dpkg --print-architecture) && \
    cd /tmp && \
    if [ "$ARCH" = "arm64" ]; then \
        wget https://github.com/microsoft/onnxruntime/releases/download/v1.24.2/onnxruntime-linux-aarch64-1.24.2.tgz && \
        tar -xzf onnxruntime-linux-aarch64-1.24.2.tgz && \
        mv onnxruntime-linux-aarch64-1.24.2 /opt/onnxruntime && \
        rm onnxruntime-linux-aarch64-1.24.2.tgz; \
    else \
        wget https://github.com/microsoft/onnxruntime/releases/download/v1.24.2/onnxruntime-linux-x64-1.24.2.tgz && \
        tar -xzf onnxruntime-linux-x64-1.24.2.tgz && \
        mv onnxruntime-linux-x64-1.24.2 /opt/onnxruntime && \
        rm onnxruntime-linux-x64-1.24.2.tgz; \
    fi

ENV ONNXRUNTIME_DIR=/opt/onnxruntime

# Copy extension source
COPY ai_extension/ /build/ai_extension/

# Build extension
RUN cd /build/ai_extension && make && make install

# ============================================================================
# Stage 2: Runtime
# ============================================================================
FROM postgres:16

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    postgresql-16-pgvector \
    wget \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# Copy ONNX Runtime from builder
COPY --from=builder /opt/onnxruntime /opt/onnxruntime
ENV LD_LIBRARY_PATH=/opt/onnxruntime/lib

# Copy built extension from builder
COPY --from=builder /usr/lib/postgresql/16/lib/ai.so /usr/lib/postgresql/16/lib/
COPY --from=builder /usr/share/postgresql/16/extension/ai.control /usr/share/postgresql/16/extension/
COPY --from=builder /usr/share/postgresql/16/extension/ai--1.0.sql /usr/share/postgresql/16/extension/

# Download model and vocabulary
RUN mkdir -p /models && \
    cd /models && \
    wget -O bge-small-en-v1.5.onnx \
    https://huggingface.co/Teradata/bge-small-en-v1.5/resolve/main/onnx/model.onnx && \
    wget -O vocab.txt \
    https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/vocab.txt

ENV AI_MODELS_PATH=/models

# Copy initialization SQL
COPY init.sql /docker-entrypoint-initdb.d/

EXPOSE 5432
