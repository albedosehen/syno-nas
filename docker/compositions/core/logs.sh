#!/bin/bash
set -euo pipefail

# ===========================================
# UNIFIED CORE SERVICES LOGS SCRIPT
# ===========================================
# Centralized log viewing and management for Synology NAS DS1520+
# Services: Portainer, SurrealDB, Doppler
# Platform: Linux/Synology DSM 7.2+
#
# Usage: ./logs.sh [OPTIONS] [SERVICE]
# Author: Synology NAS Core Services Team
# Version: 1.0.0

# Color output for better logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly PROJECT_NAME="core-services"

# Global variables
VERBOSE=false
FOLLOW_LOGS=false
TAIL_LINES=50
SERVICE_FILTER=""
EXPORT_LOGS=false
EXPORT_PATH=""
SINCE=""
UNTIL=""
SHOW_TIMESTAMPS=true
FILTER_LEVEL=""
COMPRESS_EXPORT=true

# Available services
readonly SERVICES=("portainer" "surrealdb" "doppler" "all")

# Logging functions
log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message"
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $message"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
}

log_debug() {
    local message="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $message"
    fi
}

# Help function
show_help() {
    cat << EOF
${CYAN}Unified Core Services Logs Viewer${NC}

${YELLOW}USAGE:${NC}
    $0 [OPTIONS] [SERVICE]

${YELLOW}DESCRIPTION:${NC}
    View, filter, and export logs from unified core services.
    Supports real-time log following, filtering, and export capabilities.
    
    Optimized for Synology NAS DS1520+ with DSM 7.2+

${YELLOW}SERVICES:${NC}
    portainer               Show Portainer container logs
    surrealdb               Show SurrealDB container logs  
    doppler                 Show Doppler container logs
    all                     Show logs from all services (default)

${YELLOW}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -f, --follow            Follow log output in real-time
    -n, --lines LINES       Number of lines to show (default: 50)
    -s, --since TIME        Show logs since timestamp (e.g., '2h', '30m', '2024-01-01')
    -u, --until TIME        Show logs until timestamp
    -t, --no-timestamps     Hide timestamps
    -l, --level LEVEL       Filter by log level (error, warn, info, debug)
    -e, --export            Export logs to file
    -o, --output PATH       Export path (default: ./logs_export_TIMESTAMP.tar.gz)
    -c, --no-compress       Don't compress exported logs
    
${YELLOW}EXAMPLES:${NC}
    $0                      # Show last 50 lines from all services
    $0 portainer            # Show Portainer logs only
    $0 -f                   # Follow all service logs in real-time
    $0 -n 100 surrealdb     # Show last 100 lines from SurrealDB
    $0 -s 1h                # Show logs from last hour
    $0 -l error             # Show only error-level logs
    $0 -e                   # Export all logs to compressed archive
    $0 -f portainer         # Follow Portainer logs in real-time

${YELLOW}TIME FORMATS:${NC}
    Relative: 30s, 5m, 2h, 1d, 1w
    Absolute: 2024-01-01, 2024-01-01T10:30:00, unix timestamp

${YELLOW}LOG LEVELS:${NC}
    error                   Show only error messages
    warn                    Show warnings and errors
    info                    Show info, warnings, and errors
    debug                   Show all log levels (most verbose)

${YELLOW}KEYBOARD SHORTCUTS (when following):${NC}
    Ctrl+C                  Stop following logs
    q                       Quit (when using less pager)

${YELLOW}EXPORT FEATURES:${NC}
    • Compressed archive with all service logs
    • Separate files for each service
    • Includes metadata and timestamps
    • Optional filtering by time range and level

For more information, see README.md
EOF
}

# Check if services are available
check_services() {
    log_debug "Checking available services..."
    
    local available_services=()
    local service_containers=("core-portainer" "core-surrealdb" "core-doppler")
    
    for container in "${service_containers[@]}"; do
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            local service_name="${container#core-}"
            available_services+=("$service_name")
            log_debug "✓ Service available: $service_name"
        else
            local service_name="${container#core-}"
            log_debug "✗ Service not found: $service_name"
        fi
    done
    
    if [[ ${#available_services[@]} -eq 0 ]]; then
        log_error "No core services found. Are the containers running?"
        log_info "Use './status.sh' to check service status"
        exit 1
    fi
    
    log_debug "Available services: ${available_services[*]}"
}

# Validate service name
validate_service() {
    local service="$1"
    
    if [[ -z "$service" ]]; then
        return 0  # Empty means all services
    fi
    
    if [[ "$service" == "all" ]]; then
        return 0
    fi
    
    # Check if service exists
    for valid_service in "${SERVICES[@]}"; do
        if [[ "$service" == "$valid_service" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid service: $service"
    log_info "Available services: ${SERVICES[*]}"
    exit 1
}

# Get container name from service name
get_container_name() {
    local service="$1"
    echo "core-${service}"
}

# Build docker logs command
build_logs_command() {
    local container="$1"
    local cmd="docker logs"
    
    # Add timestamps unless disabled
    if [[ "$SHOW_TIMESTAMPS" == true ]]; then
        cmd="$cmd --timestamps"
    fi
    
    # Add follow option
    if [[ "$FOLLOW_LOGS" == true ]]; then
        cmd="$cmd --follow"
    fi
    
    # Add tail lines
    if [[ -n "$TAIL_LINES" ]] && [[ "$FOLLOW_LOGS" == false ]]; then
        cmd="$cmd --tail $TAIL_LINES"
    fi
    
    # Add since time
    if [[ -n "$SINCE" ]]; then
        cmd="$cmd --since $SINCE"
    fi
    
    # Add until time
    if [[ -n "$UNTIL" ]]; then
        cmd="$cmd --until $UNTIL"
    fi
    
    cmd="$cmd $container"
    echo "$cmd"
}

# Filter logs by level
filter_logs_by_level() {
    local level="$1"
    
    case "$level" in
        "error")
            grep -i -E "(error|fatal|critical|fail)"
            ;;
        "warn")
            grep -i -E "(error|fatal|critical|fail|warn|warning)"
            ;;
        "info")
            grep -i -E "(error|fatal|critical|fail|warn|warning|info)"
            ;;
        "debug")
            cat  # Show everything
            ;;
        *)
            log_error "Invalid log level: $level"
            exit 1
            ;;
    esac
}

# Show logs for a single service
show_service_logs() {
    local service="$1"
    local container
    container=$(get_container_name "$service")
    
    # Check if container exists
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        log_warn "Container $container not found"
        return 1
    fi
    
    # Check if container is running for follow mode
    if [[ "$FOLLOW_LOGS" == true ]] && ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        log_warn "Container $container is not running. Cannot follow logs."
        log_info "Showing available logs from stopped container..."
        FOLLOW_LOGS=false
    fi
    
    local cmd
    cmd=$(build_logs_command "$container")
    
    log_debug "Executing: $cmd"
    
    if [[ -n "$FILTER_LEVEL" ]]; then
        eval "$cmd" 2>&1 | filter_logs_by_level "$FILTER_LEVEL"
    else
        eval "$cmd" 2>&1
    fi
}

# Show logs for all services
show_all_logs() {
    local services=("portainer" "surrealdb" "doppler")
    
    if [[ "$FOLLOW_LOGS" == true ]]; then
        # For follow mode, use docker-compose logs
        local compose_cmd="docker-compose logs"
        
        if [[ "$SHOW_TIMESTAMPS" == true ]]; then
            compose_cmd="$compose_cmd --timestamps"
        fi
        
        compose_cmd="$compose_cmd --follow"
        
        if [[ -n "$TAIL_LINES" ]]; then
            compose_cmd="$compose_cmd --tail $TAIL_LINES"
        fi
        
        log_debug "Following all services with: $compose_cmd"
        
        if [[ -n "$FILTER_LEVEL" ]]; then
            eval "$compose_cmd" 2>&1 | filter_logs_by_level "$FILTER_LEVEL"
        else
            eval "$compose_cmd" 2>&1
        fi
    else
        # For static logs, show each service separately
        for service in "${services[@]}"; do
            local container
            container=$(get_container_name "$service")
            
            if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
                echo
                echo -e "${PURPLE}=== $service LOGS ===${NC}"
                echo
                show_service_logs "$service"
            fi
        done
    fi
}

# Export logs to files
export_logs() {
    log_info "Exporting logs..."
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local export_dir="/tmp/core-logs-export-$timestamp"
    
    if [[ -z "$EXPORT_PATH" ]]; then
        EXPORT_PATH="./logs_export_${timestamp}.tar.gz"
    fi
    
    mkdir -p "$export_dir"
    
    # Export individual service logs
    local services=("portainer" "surrealdb" "doppler")
    local exported_count=0
    
    for service in "${services[@]}"; do
        local container
        container=$(get_container_name "$service")
        
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            log_debug "Exporting logs for: $service"
            
            local log_file="${export_dir}/${service}.log"
            local cmd
            cmd=$(build_logs_command "$container")
            
            # Remove follow option for export
            cmd=$(echo "$cmd" | sed 's/--follow//')
            
            if [[ -n "$FILTER_LEVEL" ]]; then
                eval "$cmd" 2>&1 | filter_logs_by_level "$FILTER_LEVEL" > "$log_file"
            else
                eval "$cmd" 2>&1 > "$log_file"
            fi
            
            ((exported_count++))
        else
            log_warn "Container $container not found, skipping export"
        fi
    done
    
    # Create metadata file
    cat > "${export_dir}/export-metadata.json" << EOF
{
  "export_info": {
    "timestamp": "$timestamp",
    "exported_by": "$(whoami)@$(hostname)",
    "script_version": "1.0.0",
    "services_exported": $exported_count,
    "export_options": {
      "tail_lines": "$TAIL_LINES",
      "since": "$SINCE",
      "until": "$UNTIL",
      "filter_level": "$FILTER_LEVEL",
      "timestamps": $SHOW_TIMESTAMPS
    }
  },
  "system_info": {
    "hostname": "$(hostname)",
    "docker_version": "$(docker --version 2>/dev/null || echo 'N/A')"
  }
}
EOF
    
    # Create archive
    if [[ "$COMPRESS_EXPORT" == true ]]; then
        log_debug "Creating compressed archive: $EXPORT_PATH"
        tar -czf "$EXPORT_PATH" -C "/tmp" "$(basename "$export_dir")"
    else
        # Create uncompressed archive
        local uncompressed_path="${EXPORT_PATH%.gz}"
        log_debug "Creating uncompressed archive: $uncompressed_path"
        tar -cf "$uncompressed_path" -C "/tmp" "$(basename "$export_dir")"
        EXPORT_PATH="$uncompressed_path"
    fi
    
    # Cleanup temporary directory
    rm -rf "$export_dir"
    
    log_info "✅ Logs exported to: $EXPORT_PATH"
    log_info "Archive contains logs from $exported_count services"
    
    # Show archive contents
    log_debug "Archive contents:"
    if [[ "$COMPRESS_EXPORT" == true ]]; then
        tar -tzf "$EXPORT_PATH" | head -10
    else
        tar -tf "$EXPORT_PATH" | head -10
    fi
}

# Show log summary
show_log_summary() {
    log_info "Core Services Log Summary"
    echo
    
    local services=("portainer" "surrealdb" "doppler")
    
    for service in "${services[@]}"; do
        local container
        container=$(get_container_name "$service")
        
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            local status="stopped"
            if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
                status="running"
            fi
            
            local log_count
            log_count=$(docker logs "$container" 2>&1 | wc -l)
            
            local last_log=""
            if [[ $log_count -gt 0 ]]; then
                last_log=$(docker logs --tail 1 --timestamps "$container" 2>&1 | head -1)
            fi
            
            echo -e "${YELLOW}$service${NC} ($status): $log_count lines"
            if [[ -n "$last_log" ]]; then
                echo "  Last: $last_log"
            fi
        else
            echo -e "${RED}$service${NC}: container not found"
        fi
    done
    
    echo
    log_info "Use '$0 [service]' to view specific service logs"
    log_info "Use '$0 -f' to follow logs in real-time"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--follow)
                FOLLOW_LOGS=true
                shift
                ;;
            -n|--lines)
                if [[ -n "$2" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    TAIL_LINES="$2"
                    shift 2
                else
                    log_error "Invalid number of lines: $2"
                    exit 1
                fi
                ;;
            -s|--since)
                if [[ -n "$2" ]]; then
                    SINCE="$2"
                    shift 2
                else
                    log_error "Since time not specified"
                    exit 1
                fi
                ;;
            -u|--until)
                if [[ -n "$2" ]]; then
                    UNTIL="$2"
                    shift 2
                else
                    log_error "Until time not specified"
                    exit 1
                fi
                ;;
            -t|--no-timestamps)
                SHOW_TIMESTAMPS=false
                shift
                ;;
            -l|--level)
                if [[ -n "$2" ]] && [[ "$2" =~ ^(error|warn|info|debug)$ ]]; then
                    FILTER_LEVEL="$2"
                    shift 2
                else
                    log_error "Invalid log level: $2 (must be: error, warn, info, debug)"
                    exit 1
                fi
                ;;
            -e|--export)
                EXPORT_LOGS=true
                shift
                ;;
            -o|--output)
                if [[ -n "$2" ]]; then
                    EXPORT_PATH="$2"
                    shift 2
                else
                    log_error "Export path not specified"
                    exit 1
                fi
                ;;
            -c|--no-compress)
                COMPRESS_EXPORT=false
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                # This should be a service name
                if [[ -z "$SERVICE_FILTER" ]]; then
                    SERVICE_FILTER="$1"
                else
                    log_error "Multiple services specified: $SERVICE_FILTER and $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# Main function
main() {
    log_debug "Starting core services log viewer..."
    log_debug "Options: VERBOSE=$VERBOSE, FOLLOW=$FOLLOW_LOGS, LINES=$TAIL_LINES, SERVICE=$SERVICE_FILTER"
    log_debug "Filters: SINCE='$SINCE', UNTIL='$UNTIL', LEVEL='$FILTER_LEVEL'"
    
    # Check prerequisites
    check_services
    
    # Validate service if specified
    validate_service "$SERVICE_FILTER"
    
    # Export mode
    if [[ "$EXPORT_LOGS" == true ]]; then
        export_logs
        return 0
    fi
    
    # Show summary if no specific service and not following
    if [[ -z "$SERVICE_FILTER" ]] && [[ "$FOLLOW_LOGS" == false ]] && [[ -z "$SINCE" ]] && [[ -z "$UNTIL" ]] && [[ -z "$FILTER_LEVEL" ]]; then
        show_log_summary
        return 0
    fi
    
    # Show logs
    if [[ -z "$SERVICE_FILTER" ]] || [[ "$SERVICE_FILTER" == "all" ]]; then
        show_all_logs
    else
        show_service_logs "$SERVICE_FILTER"
    fi
}

# Handle Ctrl+C gracefully
trap 'echo; log_info "Log viewing stopped"; exit 0' SIGINT

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi