#!/bin/bash

set -euo pipefail

SURREALDB_ENDPOINT="${SURREALDB_ENDPOINT:-http://core-surrealdb:8000}"
BACKUP_DIR="/backups"
TEMP_DIR="/backups/temp"
LOG_DIR="/logs/surrealdb-backup"

log_json() {
    local level="$1"
    local component="$2"
    local message="$3"
    local backup_type="${4:-}"
    local status="${5:-}"
    local duration_ms="${6:-}"
    local file_size_bytes="${7:-}"
    local compressed_size_bytes="${8:-}"
    
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    cat << EOF | tee -a "${LOG_DIR}/backup.log"
{
  "timestamp": "${timestamp}",
  "level": "${level}",
  "component": "${component}",
  "message": "${message}",
  "backup_type": "${backup_type}",
  "status": "${status}",
  "duration_ms": ${duration_ms:-null},
  "file_size_bytes": ${file_size_bytes:-null},
  "compressed_size_bytes": ${compressed_size_bytes:-null}
}
EOF
}

wait_for_keyvault() {
    local max_wait=60
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if [[ -f "/keyvault/surrealdb/username" && -f "/keyvault/surrealdb/password" ]]; then
            log_json "INFO" "surrealdb-backup" "Keyvault credentials available"
            return 0
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    log_json "ERROR" "surrealdb-backup" "Timeout waiting for keyvault credentials"
    return 1
}

read_credentials() {
    if ! wait_for_keyvault; then
        return 1
    fi
    
    SURREALDB_USERNAME=$(cat /keyvault/surrealdb/username)
    SURREALDB_PASSWORD=$(cat /keyvault/surrealdb/password)
    SURREALDB_NAMESPACE=$(cat /keyvault/surrealdb/namespace)
    SURREALDB_DATABASE=$(cat /keyvault/surrealdb/database)
    
    export SURREALDB_USERNAME SURREALDB_PASSWORD SURREALDB_NAMESPACE SURREALDB_DATABASE
}

health_check() {
    local max_retries=3
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        if curl -f -s "${SURREALDB_ENDPOINT}/health" > /dev/null 2>&1; then
            log_json "INFO" "surrealdb-backup" "SurrealDB health check passed"
            return 0
        fi
        retry=$((retry + 1))
        sleep 5
    done
    
    log_json "ERROR" "surrealdb-backup" "SurrealDB health check failed after ${max_retries} attempts"
    return 1
}

validate_export() {
    local export_file="$1"
    
    if [[ ! -f "$export_file" ]]; then
        log_json "ERROR" "surrealdb-backup" "Export file does not exist: $export_file"
        return 1
    fi
    
    if [[ ! -s "$export_file" ]]; then
        log_json "ERROR" "surrealdb-backup" "Export file is empty: $export_file"
        return 1
    fi
    
    if ! grep -q "BEGIN TRANSACTION" "$export_file"; then
        log_json "ERROR" "surrealdb-backup" "Export file does not contain valid SurrealQL structure"
        return 1
    fi
    
    log_json "INFO" "surrealdb-backup" "Export file validation passed"
    return 0
}

perform_backup() {
    local backup_type="$1"
    local target_file="$2"
    local start_time=$(date +%s%3N)
    
    log_json "INFO" "surrealdb-backup" "Starting ${backup_type} backup" "$backup_type" "started"
    
    if ! read_credentials; then
        log_json "ERROR" "surrealdb-backup" "Failed to read credentials" "$backup_type" "failed"
        return 1
    fi
    
    if ! health_check; then
        log_json "ERROR" "surrealdb-backup" "Pre-backup health check failed" "$backup_type" "failed"
        return 1
    fi
    
    local temp_file="${TEMP_DIR}/${backup_type}_$(date +%s).surql"
    local temp_compressed="${temp_file}.gz"
    
    mkdir -p "$TEMP_DIR"
    
    if ! /usr/local/bin/surreal export \
        --endpoint "$SURREALDB_ENDPOINT" \
        --username "$SURREALDB_USERNAME" \
        --password "$SURREALDB_PASSWORD" \
        --namespace "$SURREALDB_NAMESPACE" \
        --database "$SURREALDB_DATABASE" \
        "$temp_file"; then
        log_json "ERROR" "surrealdb-backup" "Export command failed" "$backup_type" "failed"
        rm -f "$temp_file"
        return 1
    fi
    
    if ! validate_export "$temp_file"; then
        log_json "ERROR" "surrealdb-backup" "Export validation failed" "$backup_type" "failed"
        rm -f "$temp_file"
        return 1
    fi
    
    local file_size=$(stat -c%s "$temp_file")
    
    if ! gzip -9 "$temp_file"; then
        log_json "ERROR" "surrealdb-backup" "Compression failed" "$backup_type" "failed"
        rm -f "$temp_file"
        return 1
    fi
    
    local compressed_size=$(stat -c%s "$temp_compressed")
    
    if ! mv "$temp_compressed" "$target_file"; then
        log_json "ERROR" "surrealdb-backup" "Failed to move backup to final location" "$backup_type" "failed"
        rm -f "$temp_compressed"
        return 1
    fi
    
    if ! gzip -t "$target_file"; then
        log_json "ERROR" "surrealdb-backup" "Post-backup integrity check failed" "$backup_type" "failed"
        return 1
    fi
    
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    
    log_json "INFO" "surrealdb-backup" "${backup_type} backup completed successfully" "$backup_type" "success" "$duration" "$file_size" "$compressed_size"
    
    rm -f "${TEMP_DIR}/${backup_type}_"*.surql*
    
    return 0
}

update_health_status() {
    local status="$1"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    cat > "${LOG_DIR}/health.log" << EOF
{
  "status": "${status}",
  "last_updated": "${timestamp}",
  "service": "surrealdb-backup"
}
EOF
}