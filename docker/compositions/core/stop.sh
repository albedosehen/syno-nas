#!/bin/bash
set -euo pipefail

# ===========================================
# UNIFIED CORE SERVICES STOP SCRIPT
# ===========================================
# Graceful shutdown script for Synology NAS DS1520+
# Services: Portainer, SurrealDB, Doppler
# Platform: Linux/Synology DSM 7.2+
#
# Usage: ./stop.sh [OPTIONS]
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
readonly LOG_FILE="${SCRIPT_DIR}/stop.log"

# Global variables
VERBOSE=false
FORCE_STOP=false
REMOVE_VOLUMES=false
REMOVE_NETWORKS=false
AUTO_CONFIRM=false
BACKUP_BEFORE_STOP=false

# Logging functions
log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

log_debug() {
    local message="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
    fi
}

log_step() {
    local step="$1"
    local message="$2"
    echo -e "${PURPLE}[STEP $step]${NC} $message" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line $line_number with exit code $exit_code"
    exit $exit_code
}

trap 'handle_error ${LINENO}' ERR

# Help function
show_help() {
    cat << EOF
${CYAN}Unified Core Services Stop Script${NC}

${YELLOW}USAGE:${NC}
    $0 [OPTIONS]

${YELLOW}DESCRIPTION:${NC}
    Gracefully stops all unified core services (Portainer, SurrealDB, Doppler)
    with optional data backup and cleanup options.
    
    Optimized for Synology NAS DS1520+ with DSM 7.2+

${YELLOW}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -f, --force             Force stop containers (kill instead of graceful stop)
    -r, --remove-volumes    Remove all data volumes (DESTRUCTIVE!)
    -n, --remove-networks   Remove Docker networks
    -b, --backup            Create backup before stopping services
    -y, --yes               Auto-confirm all prompts
    
${YELLOW}EXAMPLES:${NC}
    $0                      # Graceful stop with prompts
    $0 -v                   # Verbose stop
    $0 -f                   # Force stop containers
    $0 -b                   # Create backup before stopping
    $0 -r -y               # Remove volumes with auto-confirm (DESTRUCTIVE!)
    $0 --backup --yes       # Backup and stop with auto-confirm

${YELLOW}STOP LEVELS:${NC}
    1. Graceful stop (default) - Allows containers to shut down cleanly
    2. Force stop (-f)         - Immediately kills containers
    3. Remove volumes (-r)     - Deletes all persistent data (DESTRUCTIVE!)
    4. Remove networks (-n)    - Removes Docker networks

${YELLOW}SAFETY FEATURES:${NC}
    • Automatic backup option before destructive operations
    • Confirmation prompts for dangerous operations
    • Graceful shutdown timeout with fallback to force stop
    • Health check verification during shutdown

${YELLOW}FILES AFFECTED:${NC}
    • Docker containers: core-portainer, core-surrealdb, core-doppler
    • Docker networks: core-network
    • Data volumes: /volume1/docker/core/ (if -r used)
    • Backup location: /volume1/docker/backups/core/ (if -b used)

For more information, see README.md
EOF
}

# Check if services are running
check_services_status() {
    log_step "1" "Checking current service status..."
    
    local containers=("core-portainer" "core-surrealdb" "core-doppler")
    local running_containers=()
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            running_containers+=("$container")
            log_debug "✓ Container $container is running"
        else
            log_debug "✗ Container $container is not running"
        fi
    done
    
    if [[ ${#running_containers[@]} -eq 0 ]]; then
        log_info "No core services are currently running"
        return 1
    fi
    
    log_info "Found ${#running_containers[@]} running containers: ${running_containers[*]}"
    return 0
}

# Create backup before stopping
create_backup() {
    if [[ "$BACKUP_BEFORE_STOP" == false ]]; then
        return 0
    fi
    
    log_step "2" "Creating backup before stopping services..."
    
    if [[ -f "${SCRIPT_DIR}/backup.sh" ]]; then
        log_debug "Running backup script..."
        bash "${SCRIPT_DIR}/backup.sh" --auto-confirm
        if [[ $? -eq 0 ]]; then
            log_info "Backup completed successfully"
        else
            log_warn "Backup failed, but continuing with stop operation"
        fi
    else
        log_warn "Backup script not found at ${SCRIPT_DIR}/backup.sh"
        
        # Manual backup as fallback
        local backup_timestamp
        backup_timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_dir="/volume1/docker/backups/core/manual_${backup_timestamp}"
        
        mkdir -p "$backup_dir"
        
        if [[ -d "/volume1/docker/core/portainer/data" ]] && [[ "$(ls -A /volume1/docker/core/portainer/data 2>/dev/null)" ]]; then
            log_debug "Creating manual Portainer backup..."
            tar -czf "${backup_dir}/portainer-backup.tar.gz" -C "/volume1/docker/core/portainer/data" . 2>/dev/null || true
        fi
        
        if [[ -d "/volume1/docker/core/surrealdb/data" ]] && [[ "$(ls -A /volume1/docker/core/surrealdb/data 2>/dev/null)" ]]; then
            log_debug "Creating manual SurrealDB backup..."
            tar -czf "${backup_dir}/surrealdb-backup.tar.gz" -C "/volume1/docker/core/surrealdb/data" . 2>/dev/null || true
        fi
        
        log_info "Manual backup created at: $backup_dir"
    fi
}

# Graceful container shutdown
graceful_stop() {
    log_step "3" "Performing graceful shutdown of services..."
    
    local timeout=30
    local containers=("core-portainer" "core-surrealdb" "core-doppler")
    
    # Stop services in reverse dependency order
    # 1. Stop Portainer and SurrealDB first (they depend on Doppler)
    # 2. Stop Doppler last (secrets provider)
    
    local shutdown_order=("core-portainer" "core-surrealdb" "core-doppler")
    
    for container in "${shutdown_order[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            log_debug "Stopping container: $container"
            
            if [[ "$FORCE_STOP" == true ]]; then
                log_debug "Force stopping container: $container"
                docker kill "$container" &>/dev/null || true
            else
                log_debug "Gracefully stopping container: $container (timeout: ${timeout}s)"
                docker stop --time="$timeout" "$container" &>/dev/null || {
                    log_warn "Graceful stop failed for $container, force stopping..."
                    docker kill "$container" &>/dev/null || true
                }
            fi
            
            # Verify container stopped
            local retry_count=0
            while docker ps --format "{{.Names}}" | grep -q "^${container}$" && [[ $retry_count -lt 10 ]]; do
                log_debug "Waiting for $container to stop..."
                sleep 2
                ((retry_count++))
            done
            
            if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
                log_error "Failed to stop container: $container"
            else
                log_info "✓ Successfully stopped: $container"
            fi
        fi
    done
}

# Stop services using docker-compose
compose_stop() {
    log_step "4" "Stopping services via docker-compose..."
    
    if [[ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in $SCRIPT_DIR"
        return 1
    fi
    
    local compose_args=""
    if [[ "$FORCE_STOP" == true ]]; then
        compose_args="--timeout 5"
    else
        compose_args="--timeout 30"
    fi
    
    log_debug "Executing: docker-compose down $compose_args"
    
    if docker-compose down $compose_args 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Docker Compose stop completed"
    else
        log_warn "Docker Compose stop encountered issues, checking container status..."
        
        # Manual cleanup if compose fails
        graceful_stop
    fi
}

# Remove containers
remove_containers() {
    log_step "5" "Removing stopped containers..."
    
    local containers=("core-portainer" "core-surrealdb" "core-doppler")
    
    for container in "${containers[@]}"; do
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            log_debug "Removing container: $container"
            docker rm "$container" &>/dev/null || {
                log_warn "Failed to remove container: $container"
            }
        fi
    done
    
    log_info "Container removal completed"
}

# Remove volumes
remove_volumes() {
    if [[ "$REMOVE_VOLUMES" == false ]]; then
        return 0
    fi
    
    log_step "6" "Removing data volumes (DESTRUCTIVE OPERATION)..."
    
    # Double confirmation for destructive operation
    if [[ "$AUTO_CONFIRM" == false ]]; then
        echo
        log_warn "⚠️  WARNING: This will permanently delete all service data!"
        log_warn "   • Portainer configurations and settings"
        log_warn "   • SurrealDB databases and data"
        log_warn "   • All container persistent data"
        echo
        read -p "Are you absolutely sure you want to continue? Type 'DELETE' to confirm: " -r
        if [[ "$REPLY" != "DELETE" ]]; then
            log_info "Volume removal cancelled by user"
            return 0
        fi
        
        read -p "Last chance! Type 'YES' to permanently delete all data: " -r
        if [[ "$REPLY" != "YES" ]]; then
            log_info "Volume removal cancelled by user"
            return 0
        fi
    fi
    
    # Remove named volumes
    local volumes=("core_portainer_data" "core_surrealdb_data")
    for volume in "${volumes[@]}"; do
        if docker volume ls --format "{{.Name}}" | grep -q "^${volume}$"; then
            log_debug "Removing volume: $volume"
            docker volume rm "$volume" &>/dev/null || {
                log_warn "Failed to remove volume: $volume"
            }
        fi
    done
    
    # Remove bind mount directories (with extreme caution)
    if [[ -d "/volume1/docker/core" ]]; then
        log_debug "Removing core data directories..."
        rm -rf "/volume1/docker/core/portainer/data"/* 2>/dev/null || true
        rm -rf "/volume1/docker/core/surrealdb/data"/* 2>/dev/null || true
        log_warn "🗑️  All service data has been permanently deleted"
    fi
    
    log_info "Volume removal completed"
}

# Remove networks
remove_networks() {
    if [[ "$REMOVE_NETWORKS" == false ]]; then
        return 0
    fi
    
    log_step "7" "Removing Docker networks..."
    
    local networks=("core-network")
    
    for network in "${networks[@]}"; do
        if docker network ls --format "{{.Name}}" | grep -q "^${network}$"; then
            log_debug "Removing network: $network"
            docker network rm "$network" &>/dev/null || {
                log_warn "Failed to remove network: $network (may be in use by other containers)"
            }
        fi
    done
    
    log_info "Network removal completed"
}

# Final verification
verify_shutdown() {
    log_step "8" "Verifying shutdown completion..."
    
    local containers=("core-portainer" "core-surrealdb" "core-doppler")
    local still_running=()
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            still_running+=("$container")
        fi
    done
    
    if [[ ${#still_running[@]} -eq 0 ]]; then
        log_info "✅ All core services have been stopped successfully"
    else
        log_warn "⚠️  Some containers are still running: ${still_running[*]}"
        log_warn "You may need to manually stop them with: docker kill ${still_running[*]}"
    fi
    
    # Check for orphaned processes
    local orphaned_containers
    orphaned_containers=$(docker ps --filter "name=core-" --format "{{.Names}}" | grep -v "^core-\(portainer\|surrealdb\|doppler\)$" || true)
    
    if [[ -n "$orphaned_containers" ]]; then
        log_warn "Found orphaned containers with 'core-' prefix: $orphaned_containers"
    fi
}

# Show shutdown summary
show_shutdown_summary() {
    log_step "9" "Shutdown Summary"
    
    local operations_performed=()
    
    operations_performed+=("Stopped core services")
    
    if [[ "$BACKUP_BEFORE_STOP" == true ]]; then
        operations_performed+=("Created backup")
    fi
    
    if [[ "$REMOVE_VOLUMES" == true ]]; then
        operations_performed+=("Removed data volumes")
    fi
    
    if [[ "$REMOVE_NETWORKS" == true ]]; then
        operations_performed+=("Removed networks")
    fi
    
    cat << EOF

${GREEN}✅ Core Services Shutdown Complete!${NC}

${YELLOW}🔧 Operations Performed:${NC}
$(printf '• %s\n' "${operations_performed[@]}")

${YELLOW}📊 Current Status:${NC}
• Containers: Stopped$(if [[ "$REMOVE_VOLUMES" == true ]]; then echo " and data removed"; fi)
• Networks: $(if [[ "$REMOVE_NETWORKS" == true ]]; then echo "Removed"; else echo "Preserved"; fi)
• Data: $(if [[ "$REMOVE_VOLUMES" == true ]]; then echo "Permanently deleted"; else echo "Preserved in /volume1/docker/core/"; fi)

${YELLOW}📁 Available Commands:${NC}
• Restart Services:    ./deploy.sh
• Check Status:        ./status.sh
• View Logs:           ./logs.sh
• Restore from Backup: See MIGRATION.md

$(if [[ "$BACKUP_BEFORE_STOP" == true ]]; then
    echo "${YELLOW}💾 Backup Location:${NC}"
    echo "• Check /volume1/docker/backups/core/ for created backups"
fi)

$(if [[ "$REMOVE_VOLUMES" == true ]]; then
    echo "${RED}⚠️  Data Removal Notice:${NC}"
    echo "• All service data has been permanently deleted"
    echo "• To restore, you must redeploy and restore from backup"
    echo "• See MIGRATION.md for data restoration procedures"
fi)

For more information, see README.md

EOF

    log_info "Shutdown completed at $(date)"
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
            -f|--force)
                FORCE_STOP=true
                shift
                ;;
            -r|--remove-volumes)
                REMOVE_VOLUMES=true
                shift
                ;;
            -n|--remove-networks)
                REMOVE_NETWORKS=true
                shift
                ;;
            -b|--backup)
                BACKUP_BEFORE_STOP=true
                shift
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main stop function
main() {
    # Initialize log file
    echo "=== Core Services Stop Started at $(date) ===" > "$LOG_FILE"
    
    log_info "Starting unified core services shutdown..."
    log_debug "Script directory: $SCRIPT_DIR"
    log_debug "Options: VERBOSE=$VERBOSE, FORCE_STOP=$FORCE_STOP, REMOVE_VOLUMES=$REMOVE_VOLUMES, REMOVE_NETWORKS=$REMOVE_NETWORKS, BACKUP_BEFORE_STOP=$BACKUP_BEFORE_STOP, AUTO_CONFIRM=$AUTO_CONFIRM"
    
    # Safety warning for destructive operations
    if [[ "$REMOVE_VOLUMES" == true ]] && [[ "$AUTO_CONFIRM" == false ]]; then
        echo
        log_warn "⚠️  DESTRUCTIVE OPERATION REQUESTED!"
        log_warn "You have requested to remove data volumes (-r/--remove-volumes)"
        log_warn "This will permanently delete all service data!"
        echo
        read -p "Continue with shutdown including volume removal? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Shutdown cancelled by user"
            exit 0
        fi
    fi
    
    # Check if services are running
    if ! check_services_status; then
        log_info "No services to stop. Exiting."
        exit 0
    fi
    
    # Execute shutdown steps
    create_backup
    compose_stop
    remove_containers
    remove_volumes
    remove_networks
    verify_shutdown
    show_shutdown_summary
    
    log_info "Stop script completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi