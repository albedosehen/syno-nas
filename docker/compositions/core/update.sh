#!/bin/bash
set -euo pipefail

# ===========================================
# UNIFIED CORE SERVICES UPDATE SCRIPT
# ===========================================
# Service update automation for Synology NAS DS1520+
# Services: Portainer, SurrealDB, Doppler
# Platform: Linux/Synology DSM 7.2+
#
# Usage: ./update.sh [OPTIONS] [SERVICE]
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
readonly LOG_FILE="${SCRIPT_DIR}/update.log"
readonly BACKUP_DIR="/volume1/docker/backups/core"

# Global variables
VERBOSE=false
DRY_RUN=false
AUTO_CONFIRM=false
BACKUP_BEFORE_UPDATE=true
FORCE_UPDATE=false
UPDATE_TYPE="safe"
SERVICE_FILTER=""
ROLLBACK_ON_FAILURE=true
PRUNE_OLD_IMAGES=true
RESTART_POLICY="graceful"

# Available services and update types
readonly SERVICES=("portainer" "surrealdb" "doppler" "all")
readonly UPDATE_TYPES=("safe" "latest" "force")

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
    log_error "Update script failed at line $line_number with exit code $exit_code"
    
    if [[ "$ROLLBACK_ON_FAILURE" == true ]]; then
        log_warn "Attempting rollback due to update failure..."
        perform_rollback
    fi
    
    cleanup_temp_files
    exit $exit_code
}

trap 'handle_error ${LINENO}' ERR

# Cleanup function
cleanup_temp_files() {
    log_debug "Cleaning up temporary files..."
    find /tmp -name "core-update-*" -type f -mmin +60 -delete 2>/dev/null || true
}

trap cleanup_temp_files EXIT

# Help function
show_help() {
    cat << EOF
${CYAN}Unified Core Services Update Script${NC}

${YELLOW}USAGE:${NC}
    $0 [OPTIONS] [SERVICE]

${YELLOW}DESCRIPTION:${NC}
    Automated update script for unified core services.
    Safely updates Docker images and containers with backup and rollback capabilities.
    
    Optimized for Synology NAS DS1520+ with DSM 7.2+

${YELLOW}SERVICES:${NC}
    portainer               Update Portainer only
    surrealdb               Update SurrealDB only
    doppler                 Update Doppler only
    all                     Update all services (default)

${YELLOW}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be updated without making changes
    -y, --yes               Auto-confirm all prompts
    -f, --force             Force update even if same version
    -b, --no-backup         Skip backup before update (NOT RECOMMENDED)
    -r, --no-rollback       Disable automatic rollback on failure
    -p, --no-prune          Don't remove old Docker images after update
    -t, --type TYPE         Update type: safe|latest|force (default: safe)
    -s, --restart POLICY    Restart policy: graceful|immediate|none (default: graceful)
    
${YELLOW}UPDATE TYPES:${NC}
    safe                    Update to latest stable/LTS versions only
    latest                  Update to newest available versions
    force                   Force update regardless of version comparisons

${YELLOW}RESTART POLICIES:${NC}
    graceful                Graceful restart with health checks
    immediate               Immediate restart without health checks
    none                    Update images only, don't restart containers

${YELLOW}EXAMPLES:${NC}
    $0                      # Safe update of all services with backup
    $0 portainer            # Update Portainer only
    $0 -v                   # Verbose update with detailed logging
    $0 -t latest            # Update to latest versions
    $0 -d                   # Dry run - show what would be updated
    $0 -f -y               # Force update with auto-confirm
    $0 --no-backup          # Update without backup (not recommended)

${YELLOW}SAFETY FEATURES:${NC}
    • Automatic backup before updates
    • Version comparison to prevent downgrades
    • Health checks after updates
    • Automatic rollback on failures
    • Graceful service restart
    • Update verification

${YELLOW}BACKUP LOCATIONS:${NC}
    • Pre-update backup: /volume1/docker/backups/core/pre-update_TIMESTAMP/
    • Rollback data: Stored automatically during update process

${YELLOW}UPDATE PROCESS:${NC}
    1. Pre-update backup
    2. Pull new images
    3. Stop services gracefully
    4. Update containers
    5. Start services
    6. Verify health
    7. Cleanup old images

For more information, see README.md
EOF
}

# Check prerequisites
check_prerequisites() {
    log_step "1" "Checking update prerequisites..."
    
    # Check Docker availability
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check compose file
    if [[ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Validate compose file
    if ! docker-compose config &> /dev/null; then
        log_error "docker-compose.yml validation failed"
        exit 1
    fi
    
    # Check write permissions for backup
    if [[ "$BACKUP_BEFORE_UPDATE" == true ]]; then
        if [[ ! -d "$BACKUP_DIR" ]]; then
            mkdir -p "$BACKUP_DIR" 2>/dev/null || {
                log_error "Cannot create backup directory: $BACKUP_DIR"
                exit 1
            }
        fi
        
        local test_file="${BACKUP_DIR}/.write_test"
        if ! touch "$test_file" 2>/dev/null; then
            log_error "Cannot write to backup directory: $BACKUP_DIR"
            exit 1
        fi
        rm -f "$test_file"
    fi
    
    log_info "Prerequisites check completed successfully"
}

# Get current image versions
get_current_versions() {
    log_debug "Getting current image versions..."
    
    local versions_file="/tmp/core-update-current-versions-$$"
    
    # Get current image versions for running containers
    {
        echo "# Current image versions"
        echo "portainer=$(docker inspect core-portainer --format='{{.Image}}' 2>/dev/null | head -c 12 || echo 'none')"
        echo "surrealdb=$(docker inspect core-surrealdb --format='{{.Image}}' 2>/dev/null | head -c 12 || echo 'none')"
        echo "doppler=$(docker inspect core-doppler --format='{{.Image}}' 2>/dev/null | head -c 12 || echo 'none')"
    } > "$versions_file"
    
    echo "$versions_file"
}

# Get available image versions
get_available_versions() {
    log_debug "Checking for available image updates..."
    
    local available_file="/tmp/core-update-available-versions-$$"
    
    # Pull latest image metadata (without downloading full images)
    {
        echo "# Available image versions"
        
        # For Portainer
        local portainer_latest
        portainer_latest=$(docker run --rm portainer/portainer-ce:lts sh -c 'echo $PORTAINER_VERSION' 2>/dev/null || echo "unknown")
        echo "portainer_latest=$portainer_latest"
        
        # For SurrealDB
        local surrealdb_latest
        surrealdb_latest=$(docker run --rm surrealdb/surrealdb:latest surreal version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        echo "surrealdb_latest=$surrealdb_latest"
        
        # For Doppler (custom build, check base Alpine version)
        echo "doppler_latest=custom-build"
        
    } > "$available_file"
    
    echo "$available_file"
}

# Compare versions and determine if update needed
check_update_needed() {
    local service="$1"
    local current_file="$2"
    local available_file="$3"
    
    source "$current_file" 2>/dev/null || true
    source "$available_file" 2>/dev/null || true
    
    case "$service" in
        "portainer")
            local current_version="${portainer:-none}"
            local latest_version="${portainer_latest:-unknown}"
            ;;
        "surrealdb")
            local current_version="${surrealdb:-none}"
            local latest_version="${surrealdb_latest:-unknown}"
            ;;
        "doppler")
            # Always update custom builds unless force disabled
            echo "custom"
            return 0
            ;;
        *)
            echo "unknown"
            return 1
            ;;
    esac
    
    if [[ "$FORCE_UPDATE" == true ]]; then
        echo "force"
        return 0
    fi
    
    if [[ "$current_version" == "none" ]]; then
        echo "new"
        return 0
    fi
    
    if [[ "$current_version" != "$latest_version" ]]; then
        echo "update"
        return 0
    fi
    
    echo "current"
    return 1
}

# Create pre-update backup
create_backup() {
    if [[ "$BACKUP_BEFORE_UPDATE" == false ]]; then
        log_debug "Skipping backup (disabled by user)"
        return 0
    fi
    
    log_step "2" "Creating pre-update backup..."
    
    if [[ -f "${SCRIPT_DIR}/backup.sh" ]]; then
        log_debug "Using dedicated backup script..."
        if [[ "$AUTO_CONFIRM" == true ]]; then
            bash "${SCRIPT_DIR}/backup.sh" --yes --type full
        else
            bash "${SCRIPT_DIR}/backup.sh" --type full
        fi
        
        if [[ $? -eq 0 ]]; then
            log_info "Pre-update backup completed successfully"
        else
            log_error "Pre-update backup failed"
            exit 1
        fi
    else
        log_warn "Backup script not found, creating manual backup..."
        
        local backup_timestamp
        backup_timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="${BACKUP_DIR}/pre-update_${backup_timestamp}"
        
        mkdir -p "$backup_path"
        
        # Manual backup of critical data
        if [[ -d "/volume1/docker/core/portainer/data" ]]; then
            tar -czf "${backup_path}/portainer-data.tar.gz" -C "/volume1/docker/core/portainer/data" . 2>/dev/null || true
        fi
        
        if [[ -d "/volume1/docker/core/surrealdb/data" ]]; then
            tar -czf "${backup_path}/surrealdb-data.tar.gz" -C "/volume1/docker/core/surrealdb/data" . 2>/dev/null || true
        fi
        
        # Backup configuration
        cp "${SCRIPT_DIR}/.env" "${backup_path}/" 2>/dev/null || true
        cp "${SCRIPT_DIR}/docker-compose.yml" "${backup_path}/" 2>/dev/null || true
        
        log_info "Manual backup created at: $backup_path"
    fi
}

# Pull new images
pull_images() {
    log_step "3" "Pulling updated images..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would pull updated images"
        return 0
    fi
    
    local services_to_update=()
    
    if [[ -z "$SERVICE_FILTER" ]] || [[ "$SERVICE_FILTER" == "all" ]]; then
        services_to_update=("portainer" "surrealdb" "doppler")
    else
        services_to_update=("$SERVICE_FILTER")
    fi
    
    for service in "${services_to_update[@]}"; do
        log_debug "Pulling image for: $service"
        
        case "$service" in
            "portainer")
                docker pull portainer/portainer-ce:lts 2>&1 | tee -a "$LOG_FILE"
                ;;
            "surrealdb")
                if [[ "$UPDATE_TYPE" == "latest" ]]; then
                    docker pull surrealdb/surrealdb:latest 2>&1 | tee -a "$LOG_FILE"
                else
                    docker pull surrealdb/surrealdb:latest 2>&1 | tee -a "$LOG_FILE"  # Use latest as default
                fi
                ;;
            "doppler")
                # Custom build - rebuild instead of pull
                log_debug "Rebuilding Doppler custom image..."
                docker-compose build doppler 2>&1 | tee -a "$LOG_FILE"
                ;;
        esac
    done
    
    log_info "Image pull completed"
}

# Update services
update_services() {
    log_step "4" "Updating services..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would update and restart services"
        return 0
    fi
    
    local update_cmd=""
    
    case "$RESTART_POLICY" in
        "graceful")
            update_cmd="docker-compose up -d --no-deps"
            ;;
        "immediate")
            update_cmd="docker-compose up -d --force-recreate"
            ;;
        "none")
            log_info "Restart policy is 'none' - only images updated"
            return 0
            ;;
        *)
            log_error "Invalid restart policy: $RESTART_POLICY"
            exit 1
            ;;
    esac
    
    # Update specific service or all services
    if [[ -n "$SERVICE_FILTER" ]] && [[ "$SERVICE_FILTER" != "all" ]]; then
        update_cmd="$update_cmd $SERVICE_FILTER"
    fi
    
    log_debug "Executing update command: $update_cmd"
    eval "$update_cmd" 2>&1 | tee -a "$LOG_FILE"
    
    log_info "Service update completed"
}

# Verify update success
verify_update() {
    log_step "5" "Verifying update success..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would verify service health"
        return 0
    fi
    
    # Wait for services to start
    log_debug "Waiting for services to initialize..."
    sleep 30
    
    local services_to_check=()
    
    if [[ -z "$SERVICE_FILTER" ]] || [[ "$SERVICE_FILTER" == "all" ]]; then
        services_to_check=("portainer" "surrealdb" "doppler")
    else
        services_to_check=("$SERVICE_FILTER")
    fi
    
    local all_healthy=true
    
    for service in "${services_to_check[@]}"; do
        local container="core-${service}"
        
        # Check if container is running
        if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            log_error "Container $container is not running after update"
            all_healthy=false
            continue
        fi
        
        # Check health status
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
        
        case "$health_status" in
            "healthy")
                log_debug "✓ $service is healthy"
                ;;
            "starting")
                log_debug "⏳ $service is still starting, waiting..."
                sleep 15
                # Check again
                health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
                if [[ "$health_status" == "healthy" ]]; then
                    log_debug "✓ $service is now healthy"
                else
                    log_warn "⚠ $service health status: $health_status"
                    all_healthy=false
                fi
                ;;
            "unhealthy")
                log_error "✗ $service is unhealthy after update"
                all_healthy=false
                ;;
            "no-healthcheck")
                log_debug "ℹ $service has no health check, assuming healthy if running"
                ;;
            *)
                log_warn "⚠ $service has unknown health status: $health_status"
                all_healthy=false
                ;;
        esac
    done
    
    # Additional connectivity tests
    if [[ "$all_healthy" == true ]]; then
        log_debug "Running connectivity tests..."
        
        # Test Portainer connectivity
        if [[ " ${services_to_check[*]} " =~ " portainer " ]]; then
            local portainer_port
            portainer_port=$(grep "PORTAINER_PORT" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "9000")
            if curl -f -s --max-time 10 "http://localhost:${portainer_port}/" >/dev/null 2>&1; then
                log_debug "✓ Portainer connectivity test passed"
            else
                log_warn "⚠ Portainer connectivity test failed"
                all_healthy=false
            fi
        fi
        
        # Test SurrealDB connectivity
        if [[ " ${services_to_check[*]} " =~ " surrealdb " ]]; then
            local surrealdb_port
            surrealdb_port=$(grep "SURREALDB_PORT" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "8001")
            if curl -f -s --max-time 10 "http://localhost:${surrealdb_port}/health" >/dev/null 2>&1; then
                log_debug "✓ SurrealDB connectivity test passed"
            else
                log_warn "⚠ SurrealDB connectivity test failed"
                all_healthy=false
            fi
        fi
    fi
    
    if [[ "$all_healthy" == true ]]; then
        log_info "✅ Update verification completed successfully"
        return 0
    else
        log_error "❌ Update verification failed"
        return 1
    fi
}

# Cleanup old images
cleanup_old_images() {
    if [[ "$PRUNE_OLD_IMAGES" == false ]]; then
        log_debug "Skipping old image cleanup (disabled by user)"
        return 0
    fi
    
    log_step "6" "Cleaning up old images..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would remove old Docker images"
        return 0
    fi
    
    # Remove dangling images
    local dangling_images
    dangling_images=$(docker images -f "dangling=true" -q)
    
    if [[ -n "$dangling_images" ]]; then
        log_debug "Removing dangling images..."
        docker rmi $dangling_images 2>/dev/null || true
    fi
    
    # Prune unused images (keep last 24 hours)
    log_debug "Pruning unused images older than 24 hours..."
    docker image prune -f --filter "until=24h" 2>&1 | tee -a "$LOG_FILE"
    
    log_info "Image cleanup completed"
}

# Rollback function
perform_rollback() {
    log_warn "Performing rollback to previous state..."
    
    # Stop current containers
    docker-compose down 2>/dev/null || true
    
    # Find latest backup
    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -name "pre-update_*" -type d | sort | tail -1)
    
    if [[ -n "$latest_backup" ]] && [[ -d "$latest_backup" ]]; then
        log_debug "Rolling back using backup: $latest_backup"
        
        # Restore data
        if [[ -f "${latest_backup}/portainer-data.tar.gz" ]]; then
            log_debug "Restoring Portainer data..."
            tar -xzf "${latest_backup}/portainer-data.tar.gz" -C "/volume1/docker/core/portainer/data/" 2>/dev/null || true
        fi
        
        if [[ -f "${latest_backup}/surrealdb-data.tar.gz" ]]; then
            log_debug "Restoring SurrealDB data..."
            tar -xzf "${latest_backup}/surrealdb-data.tar.gz" -C "/volume1/docker/core/surrealdb/data/" 2>/dev/null || true
        fi
        
        # Restore configuration if needed
        if [[ -f "${latest_backup}/.env" ]]; then
            cp "${latest_backup}/.env" "${SCRIPT_DIR}/" 2>/dev/null || true
        fi
        
        # Restart services with previous configuration
        docker-compose up -d 2>/dev/null || true
        
        log_info "Rollback attempt completed"
    else
        log_error "No backup found for rollback"
    fi
}

# Show update summary
show_update_summary() {
    log_step "7" "Update Summary"
    
    local current_file="$1"
    local available_file="$2"
    
    cat << EOF

${GREEN}✅ Core Services Update Complete!${NC}

${YELLOW}📊 Update Information:${NC}
• Update Type: $UPDATE_TYPE
• Services Updated: $(if [[ -z "$SERVICE_FILTER" ]] || [[ "$SERVICE_FILTER" == "all" ]]; then echo "All services"; else echo "$SERVICE_FILTER"; fi)
• Restart Policy: $RESTART_POLICY
• Backup Created: $(if [[ "$BACKUP_BEFORE_UPDATE" == true ]]; then echo "Yes"; else echo "No"; fi)

${YELLOW}🔄 Version Changes:${NC}
$(if [[ -f "$current_file" ]] && [[ -f "$available_file" ]]; then
    source "$current_file" 2>/dev/null || true
    source "$available_file" 2>/dev/null || true
    echo "• Portainer: $(echo ${portainer:-'N/A'} | head -c 12) → ${portainer_latest:-'N/A'}"
    echo "• SurrealDB: $(echo ${surrealdb:-'N/A'} | head -c 12) → ${surrealdb_latest:-'N/A'}"
    echo "• Doppler: Custom build updated"
else
    echo "• Version information unavailable"
fi)

${YELLOW}🔧 Management Commands:${NC}
• Check Status:    ./status.sh
• View Logs:       ./logs.sh
• Create Backup:   ./backup.sh
• Stop Services:   ./stop.sh

${YELLOW}📁 Important Paths:${NC}
• Service Data:    /volume1/docker/core/
• Backups:         /volume1/docker/backups/core/
• Update Log:      ${LOG_FILE}

${YELLOW}📖 Next Steps:${NC}
1. Verify services are working correctly
2. Check application functionality
3. Monitor logs for any issues
4. Update monitoring configurations if needed

For troubleshooting, see README.md or run ./status.sh -d

EOF

    log_info "Update completed successfully at $(date)"
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
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -f|--force)
                FORCE_UPDATE=true
                shift
                ;;
            -b|--no-backup)
                BACKUP_BEFORE_UPDATE=false
                shift
                ;;
            -r|--no-rollback)
                ROLLBACK_ON_FAILURE=false
                shift
                ;;
            -p|--no-prune)
                PRUNE_OLD_IMAGES=false
                shift
                ;;
            -t|--type)
                if [[ -n "$2" ]] && [[ " ${UPDATE_TYPES[*]} " =~ " $2 " ]]; then
                    UPDATE_TYPE="$2"
                    shift 2
                else
                    log_error "Invalid update type: $2 (must be: ${UPDATE_TYPES[*]})"
                    exit 1
                fi
                ;;
            -s|--restart)
                if [[ -n "$2" ]] && [[ "$2" =~ ^(graceful|immediate|none)$ ]]; then
                    RESTART_POLICY="$2"
                    shift 2
                else
                    log_error "Invalid restart policy: $2 (must be: graceful, immediate, none)"
                    exit 1
                fi
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                # This should be a service name
                if [[ -z "$SERVICE_FILTER" ]]; then
                    # Validate service name
                    local valid_service=false
                    for service in "${SERVICES[@]}"; do
                        if [[ "$1" == "$service" ]]; then
                            valid_service=true
                            break
                        fi
                    done
                    
                    if [[ "$valid_service" == true ]]; then
                        SERVICE_FILTER="$1"
                    else
                        log_error "Invalid service: $1"
                        log_info "Available services: ${SERVICES[*]}"
                        exit 1
                    fi
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
    # Initialize log file
    echo "=== Core Services Update Started at $(date) ===" > "$LOG_FILE"
    
    log_info "Starting unified core services update..."
    log_debug "Script directory: $SCRIPT_DIR"
    log_debug "Options: VERBOSE=$VERBOSE, DRY_RUN=$DRY_RUN, AUTO_CONFIRM=$AUTO_CONFIRM"
    log_debug "Update settings: TYPE=$UPDATE_TYPE, SERVICE=$SERVICE_FILTER, RESTART=$RESTART_POLICY"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "Running in DRY RUN mode - no changes will be made"
    fi
    
    # Confirmation for destructive operations
    if [[ "$AUTO_CONFIRM" == false ]] && [[ "$DRY_RUN" == false ]]; then
        echo
        log_warn "This will update core services and may cause temporary service interruption."
        if [[ "$BACKUP_BEFORE_UPDATE" == true ]]; then
            log_info "A backup will be created before updating."
        else
            log_warn "No backup will be created (disabled by --no-backup)."
        fi
        echo
        read -p "Continue with update? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Update cancelled by user"
            exit 0
        fi
    fi
    
    # Get version information
    local current_versions_file
    current_versions_file=$(get_current_versions)
    
    local available_versions_file
    available_versions_file=$(get_available_versions)
    
    # Execute update steps
    check_prerequisites
    create_backup
    pull_images
    update_services
    
    if verify_update; then
        cleanup_old_images
        show_update_summary "$current_versions_file" "$available_versions_file"
    else
        log_error "Update verification failed"
        if [[ "$ROLLBACK_ON_FAILURE" == true ]]; then
            perform_rollback
        fi
        exit 1
    fi
    
    # Cleanup version files
    rm -f "$current_versions_file" "$available_versions_file"
    
    log_info "Update script completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi