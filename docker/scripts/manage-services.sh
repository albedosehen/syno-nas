#!/bin/bash

# Synology NAS Docker Management - Multi-Service Management Script
# This script provides centralized management for multiple Docker services
# with support for start, stop, restart, status operations across categories

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_service() {
    echo -e "${CYAN}[SERVICE]${NC} $1"
}

# Help function
show_help() {
    echo "Synology NAS Docker Management - Service Management Script"
    echo ""
    echo "Usage: $0 <action> [options]"
    echo ""
    echo "Actions:"
    echo "  start          Start services"
    echo "  stop           Stop services"
    echo "  restart        Restart services"
    echo "  status         Show service status"
    echo "  logs           Show service logs"
    echo "  pull           Pull latest images"
    echo "  ps             Show container processes"
    echo ""
    echo "Options:"
    echo "  -c, --category CATEGORY    Target specific category"
    echo "                            (management, media, productivity, networking)"
    echo "  -s, --service SERVICE      Target specific service"
    echo "  -a, --all                 Target all services (default)"
    echo "  -p, --parallel            Enable parallel operations"
    echo "  -f, --follow              Follow logs (for logs action)"
    echo "  --since DURATION          Show logs since duration (e.g., 1h, 30m)"
    echo "  --tail LINES              Number of log lines to show"
    echo "  --dry-run                 Show what would be done without executing"
    echo "  --verbose                 Enable verbose output"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start -c management     Start all management services"
    echo "  $0 stop -s portainer       Stop Portainer service"
    echo "  $0 restart -a              Restart all services"
    echo "  $0 status                  Show status of all services"
    echo "  $0 logs -s portainer -f    Follow Portainer logs"
    echo "  $0 pull -c management      Pull latest images for management services"
    echo ""
}

# Parse command line arguments
ACTION=""
TARGET_CATEGORY=""
TARGET_SERVICE=""
TARGET_ALL=true
PARALLEL_OPERATIONS=false
FOLLOW_LOGS=false
LOG_SINCE=""
LOG_TAIL=""
DRY_RUN=false
VERBOSE=false

# Parse action (required first argument)
if [ $# -eq 0 ]; then
    log_error "Action is required"
    show_help
    exit 1
fi

ACTION="$1"
shift

# Validate action
case "$ACTION" in
    start|stop|restart|status|logs|pull|ps)
        ;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    *)
        log_error "Unknown action: $ACTION"
        show_help
        exit 1
        ;;
esac

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--category)
            TARGET_CATEGORY="$2"
            TARGET_ALL=false
            shift 2
            ;;
        -s|--service)
            TARGET_SERVICE="$2"
            TARGET_ALL=false
            shift 2
            ;;
        -a|--all)
            TARGET_ALL=true
            shift
            ;;
        -p|--parallel)
            PARALLEL_OPERATIONS=true
            shift
            ;;
        -f|--follow)
            FOLLOW_LOGS=true
            shift
            ;;
        --since)
            LOG_SINCE="$2"
            shift 2
            ;;
        --tail)
            LOG_TAIL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Load global configuration
load_global_config() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
    
    # Set defaults
    MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-4}
    PARALLEL_OPERATIONS_GLOBAL=${PARALLEL_OPERATIONS:-true}
}

# Enhanced logging with verbose mode
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        log_info "VERBOSE: $1"
    fi
}

# Discover services
discover_services() {
    local category="${1:-all}"
    local service_name="${2:-}"
    local services=()
    
    verbose_log "Discovering services - category: $category, service: $service_name"
    
    if [ -n "$service_name" ]; then
        # Find specific service
        while IFS= read -r -d '' compose_file; do
            local service_dir=$(dirname "$compose_file")
            local current_service=$(basename "$service_dir")
            if [ "$current_service" = "$service_name" ]; then
                services+=("$service_dir")
                break
            fi
        done < <(find "$COMPOSITIONS_DIR" -name "docker-compose.yml" -print0 2>/dev/null)
    elif [ "$category" = "all" ]; then
        # Find all services
        while IFS= read -r -d '' compose_file; do
            local service_dir=$(dirname "$compose_file")
            services+=("$service_dir")
        done < <(find "$COMPOSITIONS_DIR" -name "docker-compose.yml" -print0 2>/dev/null)
    else
        # Find services in specific category
        local category_dir="$COMPOSITIONS_DIR/$category"
        if [ -d "$category_dir" ]; then
            while IFS= read -r -d '' compose_file; do
                local service_dir=$(dirname "$compose_file")
                services+=("$service_dir")
            done < <(find "$category_dir" -name "docker-compose.yml" -print0 2>/dev/null)
        fi
    fi
    
    echo "${services[@]}"
}

# Get service metadata
get_service_info() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    echo "$category/$service_name"
}

# Execute action on single service
execute_service_action() {
    local service_dir="$1"
    local action="$2"
    local service_info=$(get_service_info "$service_dir")
    
    if [ ! -d "$service_dir" ]; then
        log_error "Service directory does not exist: $service_dir"
        return 1
    fi
    
    if [ ! -f "$service_dir/docker-compose.yml" ]; then
        log_error "No docker-compose.yml found in $service_dir"
        return 1
    fi
    
    cd "$service_dir"
    
    case "$action" in
        start)
            log_service "Starting $service_info"
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would execute docker-compose start"
            else
                docker-compose start
                log_success "Started $service_info"
            fi
            ;;
        stop)
            log_service "Stopping $service_info"
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would execute docker-compose stop"
            else
                docker-compose stop
                log_success "Stopped $service_info"
            fi
            ;;
        restart)
            log_service "Restarting $service_info"
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would execute docker-compose restart"
            else
                docker-compose restart
                log_success "Restarted $service_info"
            fi
            ;;
        status)
            log_service "Status of $service_info"
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would execute docker-compose ps"
            else
                docker-compose ps
            fi
            ;;
        logs)
            log_service "Logs for $service_info"
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would show logs for $service_info"
            else
                local log_cmd="docker-compose logs"
                
                if [ "$FOLLOW_LOGS" = true ]; then
                    log_cmd="$log_cmd -f"
                fi
                
                if [ -n "$LOG_SINCE" ]; then
                    log_cmd="$log_cmd --since $LOG_SINCE"
                fi
                
                if [ -n "$LOG_TAIL" ]; then
                    log_cmd="$log_cmd --tail $LOG_TAIL"
                fi
                
                eval "$log_cmd"
            fi
            ;;
        pull)
            log_service "Pulling images for $service_info"
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would execute docker-compose pull"
            else
                docker-compose pull
                log_success "Pulled images for $service_info"
            fi
            ;;
        ps)
            log_service "Processes for $service_info"
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would show processes for $service_info"
            else
                docker-compose ps
            fi
            ;;
        *)
            log_error "Unknown action: $action"
            return 1
            ;;
    esac
    
    return 0
}

# Execute action on multiple services in parallel
execute_parallel() {
    local action="$1"
    shift
    local services=("$@")
    local pids=()
    local max_jobs=${MAX_PARALLEL_JOBS:-4}
    
    log_info "Executing '$action' on ${#services[@]} services in parallel (max $max_jobs jobs)"
    
    for service in "${services[@]}"; do
        # Limit concurrent jobs
        while [ ${#pids[@]} -ge $max_jobs ]; do
            # Wait for any job to complete
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            pids=("${new_pids[@]}")
            sleep 1
        done
        
        # Start action in background
        execute_service_action "$service" "$action" &
        pids+=($!)
    done
    
    # Wait for all remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Execute action on multiple services sequentially
execute_sequential() {
    local action="$1"
    shift
    local services=("$@")
    
    log_info "Executing '$action' on ${#services[@]} services sequentially"
    
    for service in "${services[@]}"; do
        execute_service_action "$service" "$action"
    done
}

# Display summary for status action
show_status_summary() {
    local services=("$@")
    
    echo ""
    echo "========================================"
    echo "        Service Status Summary"
    echo "========================================"
    echo ""
    
    printf "%-20s %-15s %-15s %s\n" "Service" "Category" "Status" "Containers"
    printf "%-20s %-15s %-15s %s\n" "--------" "--------" "------" "----------"
    
    for service_dir in "${services[@]}"; do
        if [ -d "$service_dir" ]; then
            local service_name=$(basename "$service_dir")
            local category=$(basename "$(dirname "$service_dir")")
            
            cd "$service_dir"
            
            # Get container status
            local containers=$(docker-compose ps --services 2>/dev/null | wc -l)
            local running=$(docker-compose ps --services --filter status=running 2>/dev/null | wc -l)
            
            local status="Stopped"
            if [ "$running" -gt 0 ]; then
                if [ "$running" -eq "$containers" ]; then
                    status="Running"
                else
                    status="Partial"
                fi
            fi
            
            printf "%-20s %-15s %-15s %d/%d\n" "$service_name" "$category" "$status" "$running" "$containers"
        fi
    done
    
    echo ""
}

# Main execution
main() {
    echo "========================================"
    echo "  Service Management - $ACTION"
    echo "========================================"
    echo ""
    
    cd "$PROJECT_ROOT"
    load_global_config
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    # Discover target services
    local services=()
    
    if [ -n "$TARGET_SERVICE" ]; then
        services=($(discover_services "all" "$TARGET_SERVICE"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "Service '$TARGET_SERVICE' not found"
            exit 1
        fi
    elif [ -n "$TARGET_CATEGORY" ]; then
        services=($(discover_services "$TARGET_CATEGORY"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "No services found in category '$TARGET_CATEGORY'"
            exit 1
        fi
    else
        # Target all services
        services=($(discover_services "all"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "No services found"
            exit 1
        fi
    fi
    
    log_info "Found ${#services[@]} services to process"
    verbose_log "Services: ${services[*]}"
    
    # Execute action
    if [ "$PARALLEL_OPERATIONS" = true ] && [ "$PARALLEL_OPERATIONS_GLOBAL" = true ] && [ ${#services[@]} -gt 1 ] && [ "$ACTION" != "logs" ]; then
        execute_parallel "$ACTION" "${services[@]}"
    else
        execute_sequential "$ACTION" "${services[@]}"
    fi
    
    # Show summary for status action
    if [ "$ACTION" = "status" ] && [ "$DRY_RUN" = false ]; then
        show_status_summary "${services[@]}"
    fi
    
    if [ "$DRY_RUN" = false ]; then
        log_success "Action '$ACTION' completed successfully!"
    else
        log_info "DRY RUN completed - no changes were made"
    fi
}

# Error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Execute main function
main "$@"