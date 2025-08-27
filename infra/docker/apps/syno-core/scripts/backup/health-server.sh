#!/bin/bash

set -euo pipefail

source /scripts/backup-utils.sh

PORT="${HEALTH_CHECK_PORT:-8080}"
LOG_DIR="/logs/surrealdb-backup"

get_health_status() {
    local health_file="${LOG_DIR}/health.log"
    
    if [[ -f "$health_file" ]]; then
        local status=$(jq -r '.status' "$health_file" 2>/dev/null || echo "unknown")
        local last_updated=$(jq -r '.last_updated' "$health_file" 2>/dev/null || echo "unknown")
        
        local current_time=$(date +%s)
        local health_time=$(date -d "$last_updated" +%s 2>/dev/null || echo "0")
        local time_diff=$((current_time - health_time))
        
        if [[ "$status" == "healthy" && $time_diff -lt 86400 ]]; then
            echo "200"
        else
            echo "503"
        fi
    else
        echo "503"
    fi
}

get_health_response() {
    local health_file="${LOG_DIR}/health.log"
    local backup_nightly="${BACKUP_DIR}/nightly_backup.surql.gz"
    local backup_weekly="${BACKUP_DIR}/weekly_backup.surql.gz"
    
    local status="unhealthy"
    local last_backup="never"
    local nightly_exists="false"
    local weekly_exists="false"
    local nightly_size=0
    local weekly_size=0
    
    if [[ -f "$health_file" ]]; then
        status=$(jq -r '.status' "$health_file" 2>/dev/null || echo "unhealthy")
        last_backup=$(jq -r '.last_updated' "$health_file" 2>/dev/null || echo "never")
    fi
    
    if [[ -f "$backup_nightly" ]]; then
        nightly_exists="true"
        nightly_size=$(stat -c%s "$backup_nightly")
    fi
    
    if [[ -f "$backup_weekly" ]]; then
        weekly_exists="true"
        weekly_size=$(stat -c%s "$backup_weekly")
    fi
    
    cat << EOF
{
  "status": "$status",
  "service": "surrealdb-backup",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "last_backup": "$last_backup",
  "backups": {
    "nightly": {
      "exists": $nightly_exists,
      "size_bytes": $nightly_size
    },
    "weekly": {
      "exists": $weekly_exists,
      "size_bytes": $weekly_size
    }
  }
}
EOF
}

handle_request() {
    local path="$1"
    
    case "$path" in
        "/health")
            local status_code=$(get_health_status)
            local response=$(get_health_response)
            
            cat << EOF
HTTP/1.1 $status_code OK
Content-Type: application/json
Content-Length: ${#response}
Connection: close

$response
EOF
            ;;
        *)
            cat << EOF
HTTP/1.1 404 Not Found
Content-Type: application/json
Content-Length: 27
Connection: close

{"error": "Not Found"}
EOF
            ;;
    esac
}

mkdir -p "$LOG_DIR"
update_health_status "starting"

log_json "INFO" "health-server" "Starting health check server on port $PORT"

while true; do
    if command -v nc >/dev/null 2>&1; then
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n$(get_health_response)" | nc -l -p "$PORT" -q 1
    else
        exec 3< <(mktemp -u)
        socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"/bin/bash -c 'read request; path=\$(echo \$request | cut -d\" \" -f2); handle_request \"\$path\"'"
    fi
done