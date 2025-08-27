#!/bin/bash

set -euo pipefail

source /scripts/backup-utils.sh

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] BACKUP_TYPE

Restore SurrealDB from backup file.

BACKUP_TYPE:
    nightly    Restore from nightly backup
    weekly     Restore from weekly backup

OPTIONS:
    -h, --help     Show this help message
    -f, --force    Skip confirmation prompt
    -v, --verify   Verify backup integrity only (don't restore)

Examples:
    $SCRIPT_NAME nightly
    $SCRIPT_NAME weekly --force
    $SCRIPT_NAME nightly --verify

EOF
}

verify_backup() {
    local backup_file="$1"
    local temp_file="${TEMP_DIR}/verify_$(date +%s).surql"
    
    log_json "INFO" "restore" "Verifying backup integrity: $backup_file"
    
    if [[ ! -f "$backup_file" ]]; then
        log_json "ERROR" "restore" "Backup file does not exist: $backup_file"
        return 1
    fi
    
    if ! gzip -t "$backup_file"; then
        log_json "ERROR" "restore" "Backup file is corrupted (gzip integrity check failed)"
        return 1
    fi
    
    if ! gunzip -c "$backup_file" > "$temp_file"; then
        log_json "ERROR" "restore" "Failed to decompress backup file"
        rm -f "$temp_file"
        return 1
    fi
    
    if ! validate_export "$temp_file"; then
        log_json "ERROR" "restore" "Backup file contains invalid SurrealQL structure"
        rm -f "$temp_file"
        return 1
    fi
    
    local file_size=$(stat -c%s "$temp_file")
    log_json "INFO" "restore" "Backup verification successful (size: $file_size bytes)"
    
    rm -f "$temp_file"
    return 0
}

perform_restore() {
    local backup_file="$1"
    local temp_file="${TEMP_DIR}/restore_$(date +%s).surql"
    local start_time=$(date +%s%3N)
    
    log_json "INFO" "restore" "Starting restore process from: $backup_file"
    
    if ! read_credentials; then
        log_json "ERROR" "restore" "Failed to read credentials"
        return 1
    fi
    
    if ! verify_backup "$backup_file"; then
        log_json "ERROR" "restore" "Backup verification failed"
        return 1
    fi
    
    log_json "INFO" "restore" "Decompressing backup file"
    if ! gunzip -c "$backup_file" > "$temp_file"; then
        log_json "ERROR" "restore" "Failed to decompress backup file"
        rm -f "$temp_file"
        return 1
    fi
    
    log_json "INFO" "restore" "Importing backup to SurrealDB"
    if ! /usr/local/bin/surreal import \
        --endpoint "$SURREALDB_ENDPOINT" \
        --username "$SURREALDB_USERNAME" \
        --password "$SURREALDB_PASSWORD" \
        --namespace "$SURREALDB_NAMESPACE" \
        --database "$SURREALDB_DATABASE" \
        "$temp_file"; then
        log_json "ERROR" "restore" "Failed to import backup"
        rm -f "$temp_file"
        return 1
    fi
    
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))
    local file_size=$(stat -c%s "$temp_file")
    
    log_json "INFO" "restore" "Restore completed successfully" "" "success" "$duration" "$file_size"
    
    rm -f "$temp_file"
    return 0
}

main() {
    local backup_type=""
    local force=false
    local verify_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -v|--verify)
                verify_only=true
                shift
                ;;
            nightly|weekly)
                backup_type="$1"
                shift
                ;;
            *)
                echo "Error: Unknown option $1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$backup_type" ]]; then
        echo "Error: BACKUP_TYPE is required" >&2
        usage >&2
        exit 1
    fi
    
    local backup_file="${BACKUP_DIR}/${backup_type}_backup.surql.gz"
    
    mkdir -p "$TEMP_DIR"
    
    if [[ "$verify_only" == true ]]; then
        verify_backup "$backup_file"
        exit $?
    fi
    
    if [[ "$force" != true ]]; then
        echo "WARNING: This will replace all data in the SurrealDB database."
        echo "Backup file: $backup_file"
        echo "Database: ${SURREALDB_ENDPOINT:-http://core-surrealdb:8000}"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Restore cancelled."
            exit 0
        fi
    fi
    
    perform_restore "$backup_file"
}

main "$@"