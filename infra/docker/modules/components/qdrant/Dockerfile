FROM qdrant/qdrant:latest

# Set default environment variables
ENV QDRANT__SERVICE__HTTP_PORT=6333
ENV QDRANT__SERVICE__GRPC_PORT=6334
ENV QDRANT__STORAGE__STORAGE_PATH=/qdrant/storage
ENV QDRANT__SERVICE__HOST=0.0.0.0

# Create storage directory with proper permissions
RUN mkdir -p /qdrant/storage && \
    chmod -R 755 /qdrant/storage

# Expose HTTP and gRPC ports
EXPOSE 6333 6334

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
    CMD curl -f http://localhost:6333/health || exit 1

# Use the default qdrant command
CMD ["./qdrant"]