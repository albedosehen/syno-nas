FROM alpine:latest

ENV PUID=1000 \
    PGID=1000 \
    TZ=UTC

RUN apk add --no-cache \
    bash \
    curl \
    gzip \
    dcron \
    su-exec \
    tzdata \
    jq \
    socat \
    && rm -rf /var/cache/apk/*

RUN curl -sSf https://install.surrealdb.com | sh \
    && chmod +x /usr/local/bin/surreal \
    && chown root:root /usr/local/bin/surreal

RUN addgroup -g $PGID surrealdb \
    && adduser -D -u $PUID -G surrealdb -s /bin/bash surrealdb

WORKDIR /app

COPY crontab /etc/crontabs/surrealdb

RUN mkdir -p /backups /logs /keyvault /scripts \
    && chown -R surrealdb:surrealdb /app /backups /logs /scripts

RUN chmod 644 /etc/crontabs/surrealdb

USER surrealdb

EXPOSE 8080

CMD ["/scripts/backup-entrypoint.sh"]