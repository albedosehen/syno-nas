#!/bin/bash

set -euo pipefail

export PATH="/usr/local/bin:$PATH"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /logs/surrealdb-backup/backup.log
}

log "Starting SurrealDB backup service..."

mkdir -p /backups/temp /logs/surrealdb-backup
chown surrealdb:surrealdb /backups/temp /logs/surrealdb-backup

log "Starting health check server..."
/scripts/health-server.sh &
HEALTH_PID=$!

log "Starting cron daemon..."
exec crond -f -l 2 -L /logs/surrealdb-backup/cron.log