# Build Configuration

All version numbers in the Dockerfile are configurable via build arguments.

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `PG_MAJOR` | `18` | PostgreSQL major version |
| `ONNX_VERSION` | `1.24.2` | ONNX Runtime version |
| `EXTENSION_VERSION` | `1.0` | Extension SQL schema version |

## Building with Default Values

```bash
docker build -t ai-native-pg:latest .
```

## Building with Custom Versions

### PostgreSQL 16 (Older Version)

```bash
docker build \
  --build-arg PG_MAJOR=16 \
  -t ai-native-pg:pg16 \
  .
```

### Different ONNX Runtime Version

```bash
docker build \
  --build-arg ONNX_VERSION=1.25.0 \
  -t ai-native-pg:onnx-1.25 \
  .
```

### Extension Version Update

```bash
docker build \
  --build-arg EXTENSION_VERSION=2.0 \
  -t ai-native-pg:v2 \
  .
```

### Multiple Overrides

```bash
docker build \
  --build-arg PG_MAJOR=17 \
  --build-arg ONNX_VERSION=1.25.0 \
  --build-arg EXTENSION_VERSION=2.0 \
  -t ai-native-pg:custom \
  .
```

## Docker Compose Example

```yaml
version: '3.8'

services:
  postgres:
    build:
      context: .
      args:
        PG_MAJOR: 18
        ONNX_VERSION: 1.24.2
        EXTENSION_VERSION: 1.0
    ports:
      - "5432:5432"
    environment:
      POSTGRES_PASSWORD: postgres
      AI_MODELS_PATH: /models
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: Build Docker image
  run: |
    docker build \
      --build-arg PG_MAJOR=${{ matrix.pg_version }} \
      --build-arg ONNX_VERSION=${{ env.ONNX_VERSION }} \
      -t ai-native-pg:pg${{ matrix.pg_version }} \
      .
  env:
    ONNX_VERSION: 1.24.2
```

### GitLab CI

```yaml
build:
  script:
    - docker build
      --build-arg PG_MAJOR=${PG_MAJOR}
      --build-arg ONNX_VERSION=${ONNX_VERSION}
      -t ai-native-pg:${CI_COMMIT_TAG}
      .
  variables:
    PG_MAJOR: "16"
    ONNX_VERSION: "1.24.2"
```

## Version Compatibility

### Tested Configurations

| PostgreSQL | ONNX Runtime | Status |
|------------|--------------|--------|
| 18 | 1.24.2 | ✅ Default |
| 16 | 1.24.2 | ✅ Tested |
| 17 | 1.24.2 | ⚠️ Untested |

### Notes

- **PostgreSQL Version**: Must have pgvector available in apt repositories
- **ONNX Runtime Version**: Must match architecture (x64/aarch64) naming convention
- **Extension Version**: Must match the SQL file name (ai--{VERSION}.sql)

## Troubleshooting

### Build Arg Not Applied

If a build arg doesn't seem to work:
1. Check it's declared after each `FROM` statement (Docker multi-stage builds)
2. Ensure it's spelled correctly (case-sensitive)
3. Use `docker build --no-cache` to force rebuild

### PostgreSQL Version Not Found

```
E: Unable to locate package postgresql-17-pgvector
```

**Solution**: The requested PostgreSQL version may not be available. Check [PostgreSQL APT Repository](https://www.postgresql.org/download/linux/debian/) for available versions.

### ONNX Runtime Download Failed

```
ERROR 404: Not Found
```

**Solution**: The requested ONNX Runtime version may not exist. Check [ONNX Runtime Releases](https://github.com/microsoft/onnxruntime/releases) for available versions.

## Best Practices

1. **Pin Versions**: Always specify exact versions in production
2. **Test Before Deploy**: Test custom build args in staging first
3. **Document Changes**: Update BUILD.md when changing default versions
4. **Cache Layers**: Use `--build-arg` consistently for better layer caching
5. **Security**: Keep ONNX Runtime updated for security patches

## Examples

### Development Build (Fast)

```bash
# Use defaults, leverages Docker cache
docker build -t ai-native-pg:dev .
```

### Production Build (Secure)

```bash
# Pin specific versions, no cache for security
docker build --no-cache \
  --build-arg PG_MAJOR=18 \
  --build-arg ONNX_VERSION=1.24.2 \
  --build-arg EXTENSION_VERSION=1.0 \
  -t ai-native-pg:prod \
  .
```

### Testing Older PostgreSQL Version

```bash
# Test with PostgreSQL 16 (stable)
docker build \
  --build-arg PG_MAJOR=16 \
  -t ai-native-pg:pg16-test \
  . && \
docker run --rm -e POSTGRES_PASSWORD=test ai-native-pg:pg16-test \
  psql -U postgres -c "SELECT version();"
```
