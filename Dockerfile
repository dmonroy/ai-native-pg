# AI-Native Postgres - Proof of Concept
# Multistage build for cleaner image

# Build arguments for version control
ARG PG_MAJOR=18
ARG ONNX_VERSION=1.24.2
ARG EXTENSION_VERSION=1.0

# ============================================================================
# Stage 1: Builder
# ============================================================================
FROM postgres:${PG_MAJOR} AS builder

# Re-declare build args for builder stage
ARG PG_MAJOR=18
ARG ONNX_VERSION=1.24.2

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-${PG_MAJOR} \
    postgresql-${PG_MAJOR}-pgvector \
    wget \
    cmake \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install ONNX Runtime (detect architecture)
RUN ARCH=$(dpkg --print-architecture) && \
    cd /tmp && \
    if [ "$ARCH" = "arm64" ]; then \
        wget https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION}/onnxruntime-linux-aarch64-${ONNX_VERSION}.tgz && \
        tar -xzf onnxruntime-linux-aarch64-${ONNX_VERSION}.tgz && \
        mv onnxruntime-linux-aarch64-${ONNX_VERSION} /opt/onnxruntime && \
        rm onnxruntime-linux-aarch64-${ONNX_VERSION}.tgz; \
    else \
        wget https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION}/onnxruntime-linux-x64-${ONNX_VERSION}.tgz && \
        tar -xzf onnxruntime-linux-x64-${ONNX_VERSION}.tgz && \
        mv onnxruntime-linux-x64-${ONNX_VERSION} /opt/onnxruntime && \
        rm onnxruntime-linux-x64-${ONNX_VERSION}.tgz; \
    fi

ENV ONNXRUNTIME_DIR=/opt/onnxruntime

# Copy extension source
COPY ai_extension/ /build/ai_extension/

# Build extension
RUN cd /build/ai_extension && make && make install

# ============================================================================
# Stage 2: Runtime
# ============================================================================
FROM postgres:${PG_MAJOR}

# Re-declare build args for runtime stage
ARG PG_MAJOR=18
ARG EXTENSION_VERSION=1.0

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    postgresql-${PG_MAJOR}-pgvector \
    wget \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# Copy ONNX Runtime from builder
COPY --from=builder /opt/onnxruntime /opt/onnxruntime
ENV LD_LIBRARY_PATH=/opt/onnxruntime/lib

# Copy built extension from builder
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/ai.so /usr/lib/postgresql/${PG_MAJOR}/lib/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/ai.control /usr/share/postgresql/${PG_MAJOR}/extension/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/ai--${EXTENSION_VERSION}.sql /usr/share/postgresql/${PG_MAJOR}/extension/

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
