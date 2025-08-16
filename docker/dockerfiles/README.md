# Custom Dockerfiles

This directory contains custom Docker images and build contexts for services that require specialized configurations, custom builds, or aren't available from official repositories. These custom images are optimized for Synology NAS environments and follow security best practices.

## Directory Structure

```
dockerfiles/
├── README.md                    # This file - Custom images overview
├── [service-name]/              # Individual service build contexts
│   ├── Dockerfile              # Docker image definition
│   ├── docker-compose.build.yml # Build configuration
│   ├── README.md               # Service-specific build documentation
│   ├── scripts/                # Build and setup scripts
│   ├── config/                 # Configuration templates
│   └── assets/                 # Static files and resources
└── shared/                     # Shared components and base images
    ├── base-images/            # Common base image configurations
    ├── scripts/                # Reusable build scripts
    └── configs/                # Common configuration templates
```

## When to Use Custom Images

Consider creating custom Docker images when:

- **Official images don't exist** for the desired service
- **Synology-specific optimizations** are needed (permissions, paths, dependencies)
- **Security hardening** requires custom configurations
- **Multiple configurations** need to be bundled into a single image
- **Complex setup procedures** would be better handled during build time
- **Performance optimizations** require compilation with specific flags

## Custom Image Categories

### Base Images (`shared/base-images/`)

Common base images optimized for Synology NAS:

*Planned base images*:
- **synology-alpine**: Alpine Linux with Synology NAS optimizations
- **synology-ubuntu**: Ubuntu base with proper user/group handling
- **synology-node**: Node.js runtime optimized for NAS environments
- **synology-python**: Python runtime with common libraries

### Service-Specific Images

Custom images for specific services that require tailored configurations:

*Example service categories*:
- **Development Tools**: Custom Git servers, CI/CD tools
- **Monitoring Solutions**: Custom monitoring stacks
- **Legacy Applications**: Older applications requiring specific dependencies
- **Security Tools**: Hardened security applications

## Build Standards

### Dockerfile Best Practices

```dockerfile
# Example: Custom service Dockerfile template

# Use official base image when possible
FROM alpine:3.18

# Metadata
LABEL maintainer="Synology NAS Docker Management Project"
LABEL description="Custom [Service Name] for Synology NAS"
LABEL version="1.0.0"

# Install system dependencies
RUN apk add --no-cache \
    curl \
    bash \
    su-exec \
    tzdata

# Create non-root user for security
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Set working directory
WORKDIR /app

# Copy application files
COPY --chown=appuser:appuser scripts/ /app/scripts/
COPY --chown=appuser:appuser config/ /app/config/

# Set executable permissions
RUN chmod +x /app/scripts/*.sh

# Create data directories
RUN mkdir -p /app/data /app/logs && \
    chown -R appuser:appuser /app/data /app/logs

# Expose ports
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Switch to non-root user
USER appuser

# Entry point
ENTRYPOINT ["/app/scripts/entrypoint.sh"]
CMD ["start"]
```

### Build Configuration

Each custom image should include a build configuration:

```yaml
# docker-compose.build.yml
services:
  service-name:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        - BUILD_DATE=${BUILD_DATE}
        - VERSION=${VERSION}
        - PUID=${PUID:-1000}
        - PGID=${PGID:-1000}
    image: synology-nas/service-name:latest
    container_name: service-name-build
    
    # Environment for testing
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-UTC}
    
    # Test volumes
    volumes:
      - ./test-data:/app/data
      - ./test-config:/app/config
    
    # Test ports
    ports:
      - "8080:8080"
```

### Security Considerations

#### Multi-Stage Builds

Use multi-stage builds to minimize attack surface:

```dockerfile
# Build stage
FROM alpine:3.18 AS builder

RUN apk add --no-cache build-base git
WORKDIR /build
COPY source/ .
RUN make build

# Runtime stage
FROM alpine:3.18 AS runtime

# Copy only necessary files from build stage
COPY --from=builder /build/dist/app /usr/local/bin/app

# Continue with minimal runtime setup...
```

#### Security Hardening

```dockerfile
# Remove package managers and build tools
RUN apk del build-base git && \
    rm -rf /var/cache/apk/*

# Set read-only filesystem where possible
VOLUME ["/app/data"]
# Mark other directories as read-only in docker-compose.yml

# Drop capabilities
# Add in docker-compose.yml:
# cap_drop:
#   - ALL
# cap_add:
#   - CHOWN
#   - SETUID
#   - SETGID
```

## Build Process

### Building Custom Images

```bash
# Navigate to service directory
cd dockerfiles/[service-name]

# Build image
docker build -t synology-nas/[service-name]:latest .

# Or use docker-compose for complex builds
docker-compose -f docker-compose.build.yml build

# Test the built image
docker-compose -f docker-compose.build.yml up -d
```

### Build Automation

```bash
# Build script template (build.sh)
#!/bin/bash

set -e

# Configuration
SERVICE_NAME="[service-name]"
IMAGE_NAME="synology-nas/${SERVICE_NAME}"
VERSION="${1:-latest}"
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Build arguments
BUILD_ARGS=(
    --build-arg BUILD_DATE="$BUILD_DATE"
    --build-arg VERSION="$VERSION"
    --build-arg PUID="${PUID:-1000}"
    --build-arg PGID="${PGID:-1000}"
)

echo "Building $IMAGE_NAME:$VERSION..."

# Build image
docker build "${BUILD_ARGS[@]}" -t "$IMAGE_NAME:$VERSION" .

# Tag as latest if version specified
if [ "$VERSION" != "latest" ]; then
    docker tag "$IMAGE_NAME:$VERSION" "$IMAGE_NAME:latest"
fi

echo "Build completed: $IMAGE_NAME:$VERSION"

# Optional: Test the image
if [ "$2" = "--test" ]; then
    echo "Testing image..."
    docker run --rm "$IMAGE_NAME:$VERSION" --version
fi
```

### Build Testing

```bash
# Test script template (test.sh)
#!/bin/bash

set -e

SERVICE_NAME="[service-name]"
IMAGE_NAME="synology-nas/${SERVICE_NAME}:latest"

echo "Testing $IMAGE_NAME..."

# Basic functionality test
docker run --rm "$IMAGE_NAME" --version

# Health check test
CONTAINER_ID=$(docker run -d -p 8080:8080 "$IMAGE_NAME")
sleep 10

# Check if service is responding
if curl -f http://localhost:8080/health; then
    echo "Health check passed"
else
    echo "Health check failed"
    docker logs "$CONTAINER_ID"
    exit 1
fi

# Cleanup
docker stop "$CONTAINER_ID"

echo "All tests passed"
```

## Integration with Compositions

### Using Custom Images

Custom images integrate seamlessly with the compositions structure:

```yaml
# In docker/compositions/[category]/[service]/docker-compose.yml
services:
  custom-service:
    image: synology-nas/custom-service:latest
    container_name: custom-service
    
    # Standard service configuration...
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-UTC}
    
    volumes:
      - ${SERVICE_DATA_PATH:-./data}:/app/data
      - ${SERVICE_CONFIG_PATH:-./config}:/app/config
```

### Build Dependencies

For services that depend on custom images:

```yaml
# docker-compose.yml with build dependency
services:
  custom-service:
    build: 
      context: ../../../dockerfiles/custom-service
      dockerfile: Dockerfile
    # Or reference pre-built image:
    # image: synology-nas/custom-service:latest
```

## Maintenance and Updates

### Image Lifecycle

1. **Development**: Create and test custom image
2. **Integration**: Integrate with service composition
3. **Deployment**: Deploy to production environment
4. **Monitoring**: Monitor for security updates and improvements
5. **Updates**: Regular rebuilds for security patches
6. **Deprecation**: Plan migration when official images become available

### Update Procedures

```bash
# Update all custom images
#!/bin/bash

for dir in */; do
    if [ -f "$dir/Dockerfile" ]; then
        echo "Building $dir..."
        cd "$dir"
        ./build.sh latest
        cd ..
    fi
done

# Restart dependent services
echo "Restarting services using custom images..."
find ../compositions -name "docker-compose.yml" -exec grep -l "synology-nas/" {} \; | \
    xargs -I {} dirname {} | \
    xargs -I {} sh -c 'cd "{}" && docker-compose pull && docker-compose up -d'
```

### Security Updates

```bash
# Security update script
#!/bin/bash

# Check for base image updates
docker pull alpine:3.18
docker pull ubuntu:22.04

# Rebuild all images
for dir in */; do
    if [ -f "$dir/Dockerfile" ]; then
        cd "$dir"
        # Rebuild without cache for security updates
        docker build --no-cache -t "synology-nas/${dir%/}:latest" .
        cd ..
    fi
done

# Update services
echo "Security updates applied. Update your services:"
echo "  cd ../compositions/[category]/[service]"
echo "  docker-compose pull && docker-compose up -d"
```

## Documentation Requirements

Each custom image must include:

### README.md Template

```markdown
# Custom [Service Name] Image

Brief description of the custom image and why it was created.

## Features

- List of custom features and optimizations
- Synology NAS-specific configurations
- Security enhancements

## Building

### Prerequisites
- Docker 20.10+
- Build dependencies (if any)

### Build Instructions
```bash
# Build commands
./build.sh latest

# Test image
./test.sh
```

## Usage

### Environment Variables
- List of build-time and runtime variables
- Default values and descriptions

### Volumes
- Required and optional volume mounts
- Data persistence considerations

### Ports
- Exposed ports and their purposes

## Security

- Security features implemented
- Known security considerations
- Update procedures

## Maintenance

- Update frequency recommendations
- Monitoring requirements
- Troubleshooting guidelines
```

## Troubleshooting

### Common Build Issues

1. **Permission Problems**:
   ```bash
   # Fix ownership in Dockerfile
   COPY --chown=appuser:appuser source/ /app/
   ```

2. **Layer Caching Issues**:
   ```bash
   # Rebuild without cache
   docker build --no-cache -t image:tag .
   ```

3. **Multi-Architecture Builds**:
   ```bash
   # Build for multiple architectures
   docker buildx build --platform linux/amd64,linux/arm64 -t image:tag .
   ```

### Build Debugging

```bash
# Debug build process
docker build --progress=plain --no-cache -t debug-image .

# Inspect build layers
docker history image:tag

# Run intermediate layer for debugging
docker run -it --rm <layer-id> /bin/sh
```

## Best Practices

### Performance Optimization

- Use multi-stage builds to reduce image size
- Combine RUN commands to minimize layers
- Use .dockerignore to exclude unnecessary files
- Order Dockerfile commands for optimal caching

### Security Best Practices

- Run as non-root user
- Use specific version tags, not 'latest'
- Scan images for vulnerabilities
- Implement proper secret management
- Use read-only filesystems where possible

### Maintainability

- Document all customizations clearly
- Use semantic versioning for custom images
- Implement automated testing
- Regular security updates and rebuilds
- Clear migration path to official images

---

**Custom Images Version**: 1.0  
**Last Updated**: 2024  
**Build Requirements**: Docker 20.10+, Synology DSM 7.2+  
**Security Review**: Quarterly recommended