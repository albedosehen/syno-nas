#!/bin/bash

set -euo pipefail

source /scripts/backup-utils.sh

BACKUP_TYPE="weekly"
TARGET_FILE="${BACKUP_DIR}/weekly_backup.surql.gz"

update_health_status "running"

if perform_backup "$BACKUP_TYPE" "$TARGET_FILE"; then
    update_health_status "healthy"
    exit 0
else
    update_health_status "unhealthy"
    exit 1
fi