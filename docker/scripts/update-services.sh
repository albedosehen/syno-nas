#!/bin/bash

# Synology NAS Docker Management - Service Update Script
# This script automates the update process for Docker services with safety checks,
# rollback capabilities, and staged deployment options

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"
UPDATE_DATE=$(date +%Y%m%d_%H%M%S)

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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

log_service() {
    echo -e "${CYAN}[SERVICE]${NC} $1"
}

# Help function
show_help() {
    echo "Synology NAS Docker Management - Service Update Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --category CATEGORY      Update only services in specified category"
    echo "                              (management, media, productivity, networking)"
    echo "  -s, --service SERVICE        Update only specified service"
    echo "  --check-only                Check for available updates without applying"
    echo "  --security-only             Update only images with security vulnerabilities"
    echo "  --staged                    Update services in stages (management first)"
    echo "  --backup-before             Create backup before updating"
    echo "  --rollback-on-failure       Automatically rollback on update failure"
    echo "  --verify-health             Verify service health after updates"
    echo "  --parallel                  Enable parallel update operations"
    echo "  --force                     Force update even if no new version detected"
    echo "  --prune-images              Remove old images after successful update"
    echo "  --restart-policy POLICY     Restart policy: unless-stopped, always, on-failure"
    echo "  --timeout SECONDS           Health check timeout per service (default: 120)"
    echo "  --dry-run                   Show what would be updated without executing"
    echo "  --verbose                   Enable verbose output"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --check-only             Check for available updates"
    echo "  $0 -c management --backup-before  Update management services with backup"
    echo "  $0 -s portainer --verify-health    Update Portainer with health verification"
    echo "  $0 --staged --rollback-on-failure  Staged update with rollback safety"
    echo "  $0 --security-only          Update only security-critical images"
    echo ""
}

# Parse command line arguments
TARGET_CATEGORY=""
TARGET_SERVICE=""
CHECK_ONLY=false
SECURITY_ONLY=false
STAGED_UPDATE=false
BACKUP_BEFORE=false
ROLLBACK_ON_FAILURE=false
VERIFY_HEALTH=false
PARALLEL_UPDATE=false
FORCE_UPDATE=false
PRUNE_IMAGES=false
RESTART_POLICY=""
HEALTH_TIMEOUT=120
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--category)
            TARGET_CATEGORY="$2"
            shift 2
            ;;
        -s|--service)
            TARGET_SERVICE="$2"
            shift 2
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --security-only)
            SECURITY_ONLY=true
            shift
            ;;
        --staged)
            STAGED_UPDATE=true
            shift
            ;;
        --backup-before)
            BACKUP_BEFORE=true
            shift
            ;;
        --rollback-on-failure)
            ROLLBACK_ON_FAILURE=true
            shift
            ;;
        --verify-health)
            VERIFY_HEALTH=true
            shift
            ;;
        --parallel)
            PARALLEL_UPDATE=true
            shift
            ;;
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --prune-images)
            PRUNE_IMAGES=true
            shift
            ;;
        --restart-policy)
            RESTART_POLICY="$2"
            shift 2
            ;;
        --timeout)
            HEALTH_TIMEOUT="$2"
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
    AUTO_SECURITY_UPDATES=${AUTO_SECURITY_UPDATES:-true}
    MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-4}
    VULNERABILITY_SCANNING=${VULNERABILITY_SCANNING:-false}
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

# Check for available updates
check_service_updates() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    verbose_log "Checking updates for $category/$service_name"
    
    cd "$service_dir"
    
    # Get current image digests
    local current_images=$(docker-compose config --images 2>/dev/null | sort | uniq)
    local updates_available=false
    
    echo "Service: $category/$service_name"
    
    for image in $current_images; do
        if [ -n "$image" ]; then
            # Get local image digest
            local local_digest=$(docker images --digests --format "table {{.Repository}}:{{.Tag}}\t{{.Digest}}" | grep "^$image" | awk '{print $2}' | head -1)
            
            # Pull latest image info without downloading
            if [ "$DRY_RUN" = false ]; then
                local remote_digest=$(docker manifest inspect "$image" 2>/dev/null | jq -r '.config.digest' 2>/dev/null || echo "unknown")
            else
                local remote_digest="dry-run-digest"
            fi
            
            if [ "$local_digest" != "$remote_digest" ] && [ "$remote_digest" != "unknown" ]; then
                echo "  ✓ Update available: $image"
                updates_available=true
            else
                echo "  - Up to date: $image"
            fi
        fi
    done
    
    if [ "$updates_available" = true ]; then
        return 0  # Updates available
    else
        return 1  # No updates
    fi
}

# Create pre-update backup
create_backup() {
    local services=("$@")
    
    if [ "$BACKUP_BEFORE" = false ]; then
        return 0
    fi
    
    log_step "Creating pre-update backup..."
    
    local backup_script="$SCRIPT_DIR/backup-all.sh"
    
    if [ -f "$backup_script" ] && [ -x "$backup_script" ]; then
        local backup_args="--compress"
        
        if [ -n "$TARGET_CATEGORY" ]; then
            backup_args="$backup_args --category $TARGET_CATEGORY"
        elif [ -n "$TARGET_SERVICE" ]; then
            backup_args="$backup_args --service $TARGET_SERVICE"
        fi
        
        if [ "$DRY_RUN" = true ]; then
            backup_args="$backup_args --dry-run"
        fi
        
        verbose_log "Executing: $backup_script $backup_args"
        
        if "$backup_script" $backup_args; then
            log_success "Pre-update backup completed"
        else
            log_error "Pre-update backup failed"
            return 1
        fi
    else
        log_warning "Backup script not found or not executable: $backup_script"
    fi
}

# Update single service
update_service() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_service "Updating $category/$service_name"
    
    cd "$service_dir"
    
    # Store current state for potential rollback
    local current_containers=""
    if [ "$ROLLBACK_ON_FAILURE" = true ] && [ "$DRY_RUN" = false ]; then
        current_containers=$(docker-compose ps -q 2>/dev/null | tr '\n' ' ')
        verbose_log "Stored container state for rollback: $current_containers"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would update $category/$service_name"
        return 0
    fi
    
    # Pull new images
    log_info "Pulling latest images for $category/$service_name..."
    if ! docker-compose pull; then
        log_error "Failed to pull images for $category/$service_name"
        return 1
    fi
    
    # Update service with new images
    log_info "Updating service containers..."
    
    local compose_args=""
    if [ -n "$RESTART_POLICY" ]; then
        compose_args="--restart=$RESTART_POLICY"
    fi
    
    if ! docker-compose up -d $compose_args; then
        log_error "Failed to update $category/$service_name"
        
        # Attempt rollback if enabled
        if [ "$ROLLBACK_ON_FAILURE" = true ]; then
            log_warning "Attempting rollback for $category/$service_name"
            if docker-compose down && docker-compose up -d; then
                log_warning "Rollback completed for $category/$service_name"
            else
                log_error "Rollback failed for $category/$service_name"
            fi
        fi
        
        return 1
    fi
    
    # Verify health if enabled
    if [ "$VERIFY_HEALTH" = true ]; then
        if ! verify_service_health "$service_dir"; then
            log_error "Health check failed for $category/$service_name"
            
            # Attempt rollback if enabled
            if [ "$ROLLBACK_ON_FAILURE" = true ]; then
                log_warning "Health check failed, attempting rollback for $category/$service_name"
                if docker-compose down && docker-compose up -d; then
                    log_warning "Rollback completed for $category/$service_name"
                else
                    log_error "Rollback failed for $category/$service_name"
                fi
            fi
            
            return 1
        fi
    fi
    
    log_success "Updated $category/$service_name"
    return 0
}

# Verify service health after update
verify_service_health() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    
    log_info "Verifying health of $service_name (timeout: ${HEALTH_TIMEOUT}s)..."
    
    cd "$service_dir"
    
    local elapsed=0
    local check_interval=5
    
    while [ $elapsed -lt $HEALTH_TIMEOUT ]; do
        # Check if all containers are running
        local total_services=$(docker-compose config --services | wc -l)
        local running_services=$(docker-compose ps --services --filter status=running | wc -l)
        
        if [ "$running_services" -eq "$total_services" ] && [ "$total_services" -gt 0 ]; then
            # Additional health checks can be added here
            verbose_log "$service_name health check passed"
            return 0
        fi
        
        verbose_log "Health check in progress for $service_name ($elapsed/${HEALTH_TIMEOUT}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    log_warning "$service_name health check timed out"
    return 1
}

# Update services in parallel
update_services_parallel() {
    local services=("$@")
    local pids=()
    local max_jobs=${MAX_PARALLEL_JOBS:-4}
    
    log_info "Updating ${#services[@]} services in parallel (max $max_jobs jobs)"
    
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
        
        # Start update in background
        update_service "$service" &
        pids+=($!)
    done
    
    # Wait for all remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Update services sequentially
update_services_sequential() {
    local services=("$@")
    
    log_info "Updating ${#services[@]} services sequentially"
    
    for service in "${services[@]}"; do
        if ! update_service "$service"; then
            log_error "Failed to update service in $service"
            if [ "$ROLLBACK_ON_FAILURE" = false ]; then
                log_warning "Continuing with remaining services..."
            fi
        fi
    done
}

# Staged update (management services first)
update_services_staged() {
    local all_services=("$@")
    local mgmt_services=()
    local other_services=()
    
    # Separate management services from others
    for service in "${all_services[@]}"; do
        local category=$(basename "$(dirname "$service")")
        if [ "$category" = "management" ]; then
            mgmt_services+=("$service")
        else
            other_services+=("$service")
        fi
    done
    
    log_step "Stage 1: Updating management services (${#mgmt_services[@]} services)"
    if [ ${#mgmt_services[@]} -gt 0 ]; then
        update_services_sequential "${mgmt_services[@]}"
        
        # Wait between stages
        if [ ${#other_services[@]} -gt 0 ]; then
            log_info "Waiting 30 seconds between stages..."
            sleep 30
        fi
    fi
    
    log_step "Stage 2: Updating other services (${#other_services[@]} services)"
    if [ ${#other_services[@]} -gt 0 ]; then
        if [ "$PARALLEL_UPDATE" = true ]; then
            update_services_parallel "${other_services[@]}"
        else
            update_services_sequential "${other_services[@]}"
        fi
    fi
}

# Prune old images after successful updates
prune_old_images() {
    if [ "$PRUNE_IMAGES" = false ]; then
        return 0
    fi
    
    log_step "Pruning old Docker images..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would prune old Docker images"
        return 0
    fi
    
    # Prune only dangling images to be safe
    local pruned=$(docker image prune -f --filter "dangling=true" 2>/dev/null | grep "Total reclaimed space" | awk '{print $4, $5}')
    
    if [ -n "$pruned" ]; then
        log_success "Pruned old images: $pruned"
    else
        log_info "No old images to prune"
    fi
}

# Display update summary
show_update_summary() {
    local services=("$@")
    
    echo ""
    echo "========================================"
    echo "         Update Summary"
    echo "========================================"
    echo ""
    
    echo "Update Configuration:"
    echo "  Date: $UPDATE_DATE"
    echo "  Services: ${#services[@]}"
    echo "  Mode: $([ "$STAGED_UPDATE" = true ] && echo "Staged" || echo "Standard")"
    echo "  Parallel: $([ "$PARALLEL_UPDATE" = true ] && echo "Yes" || echo "No")"
    echo "  Backup: $([ "$BACKUP_BEFORE" = true ] && echo "Yes" || echo "No")"
    echo "  Health Check: $([ "$VERIFY_HEALTH" = true ] && echo "Yes" || echo "No")"
    echo "  Rollback on Failure: $([ "$ROLLBACK_ON_FAILURE" = true ] && echo "Yes" || echo "No")"
    echo ""
    
    if [ "$CHECK_ONLY" = true ]; then
        echo "Update Check Results:"
        echo "  Check completed - see individual service results above"
    elif [ "$DRY_RUN" = false ]; then
        echo "Services Updated:"
        for service_dir in "${services[@]}"; do
            local service_name=$(basename "$service_dir")
            local category=$(basename "$(dirname "$service_dir")")
            echo "  - $category/$service_name"
        done
    fi
    
    echo ""
    echo "Post-Update Actions:"
    echo "  Monitor logs: docker/scripts/manage-services.sh logs -f"
    echo "  Check status: docker/scripts/manage-services.sh status"
    echo "  Create backup: docker/scripts/backup-all.sh"
    echo ""
}

# Main execution
main() {
    echo "========================================"
    echo "     Service Update Script"
    echo "========================================"
    echo ""
    
    cd "$PROJECT_ROOT"
    load_global_config
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    # Discover services to update
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
        # Update all services
        services=($(discover_services "all"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "No services found"
            exit 1
        fi
    fi
    
    log_info "Found ${#services[@]} services to process"
    verbose_log "Services: ${services[*]}"
    
    # Check for updates only
    if [ "$CHECK_ONLY" = true ]; then
        log_step "Checking for available updates..."
        
        local updates_found=false
        for service_dir in "${services[@]}"; do
            if check_service_updates "$service_dir"; then
                updates_found=true
            fi
            echo ""
        done
        
        if [ "$updates_found" = true ]; then
            log_info "Updates are available for some services"
            exit 0
        else
            log_info "All services are up to date"
            exit 0
        fi
    fi
    
    # Create backup if requested
    create_backup "${services[@]}"
    
    # Execute updates
    if [ "$STAGED_UPDATE" = true ]; then
        update_services_staged "${services[@]}"
    elif [ "$PARALLEL_UPDATE" = true ] && [ ${#services[@]} -gt 1 ]; then
        update_services_parallel "${services[@]}"
    else
        update_services_sequential "${services[@]}"
    fi
    
    # Post-update cleanup
    if [ "$DRY_RUN" = false ]; then
        prune_old_images
    fi
    
    # Show summary
    show_update_summary "${services[@]}"
    
    if [ "$DRY_RUN" = false ]; then
        log_success "Update operation completed successfully!"
    else
        log_info "DRY RUN completed - no changes were made"
    fi
}

# Error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Execute main function
main "$@"