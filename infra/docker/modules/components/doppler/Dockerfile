FROM alpine:latest

# Install dependencies for Doppler CLI
RUN apk add --no-cache \
    curl \
    ca-certificates \
    gnupg \
    bash \
    jq \
    && rm -rf /var/cache/apk/*

# Install Doppler CLI
RUN curl -Ls --tlsv1.2 --proto "=https" --retry 3 \
    https://packages.doppler.com/public/cli/rsa.8004D9FF50437357.key | \
    gpg --import && \
    curl -Ls --tlsv1.2 --proto "=https" --retry 3 \
    https://github.com/DopplerHQ/cli/releases/latest/download/doppler_linux_amd64.tar.gz | \
    tar -xzO doppler > /usr/local/bin/doppler && \
    chmod +x /usr/local/bin/doppler

# Verify installation
RUN doppler --version

# Create app directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1000 doppler && \
    adduser -D -s /bin/bash -u 1000 -G doppler doppler

# Switch to non-root user
USER doppler

# Health check to verify Doppler is working
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD doppler --version || exit 1

# Entry point script
COPY --chown=doppler:doppler docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["doppler", "run", "--", "printenv"]