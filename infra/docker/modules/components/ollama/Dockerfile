FROM ollama/ollama:latest

RUN apt-get update && \
    apt-get install -y curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV OLLAMA_HOST=0.0.0.0
ENV OLLAMA_PORT=11434
ENV OLLAMA_ORIGINS=*
ENV OLLAMA_DATA_DIR=/root/.ollama

# Data directoryu
RUN mkdir -p /root/.ollama && \
    chmod -R 755 /root/.ollama

EXPOSE 11434

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -f http://localhost:11434/api/version || exit 1

CMD ["ollama", "serve"]