#!/bin/bash

# Synology NAS Docker Management - System Cleanup Script
# This script performs comprehensive cleanup of Docker resources,
# logs, temporary files, and system maintenance tasks

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"
CLEANUP_DATE=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Cleanup tracking
CLEANUP_ITEMS=0
CLEANUP_SPACE_FREED=""
CLEANUP_ERRORS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((CLEANUP_ITEMS++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((CLEANUP_ERRORS++))
}

log_step() {
    echo -e "${PURPLE}[CLEANUP]${NC} $1"
}

log_service() {
    echo -e "${CYAN}[SERVICE]${NC} $1"
}

# Help function
show_help() {
    echo "Synology NAS Docker Management - System Cleanup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --docker-system             Clean Docker system (images, containers, networks, volumes)"
    echo "  --docker-images             Remove unused Docker images"
    echo "  --docker-containers         Remove stopped containers"
    echo "  --docker-volumes            Remove unused volumes"
    echo "  --docker-networks           Remove unused networks"
    echo "  --logs                      Clean and rotate log files"
    echo "  --project-logs              Clean project-specific log files"
    echo "  --service-logs              Clean service log files"
    echo "  --temp-files                Remove temporary files"
    echo "  --backup-cleanup            Clean old backup files"
    echo "  --aggressive                Perform aggressive cleanup (removes more data)"
    echo "  --preserve-days DAYS        Preserve files newer than DAYS (default: 7)"
    echo "  --preserve-running          Preserve resources for running containers only"
    echo "  --dry-run                   Show what would be cleaned without executing"
    echo "  --force                     Skip confirmation prompts"
    echo "  --verbose                   Enable verbose output"
    echo "  --report                    Generate cleanup report"
    echo "  --all                       Perform all cleanup operations (default)"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          Perform all cleanup operations"
    echo "  $0 --docker-images --dry-run   Show what Docker images would be removed"
    echo "  $0 --aggressive --preserve-days 3  Aggressive cleanup preserving 3 days"
    echo "  $0 --logs --temp-files      Clean only logs and temporary files"
    echo "  $0 --backup-cleanup --preserve-days 30  Clean backups older than 30 days"
    echo ""
}

# Parse command line arguments
CLEANUP_DOCKER_SYSTEM=false
CLEANUP_DOCKER_IMAGES=false
CLEANUP_DOCKER_CONTAINERS=false
CLEANUP_DOCKER_VOLUMES=false
CLEANUP_DOCKER_NETWORKS=false
CLEANUP_LOGS=false
CLEANUP_PROJECT_LOGS=false
CLEANUP_SERVICE_LOGS=false
CLEANUP_TEMP_FILES=false
CLEANUP_BACKUPS=false
AGGRESSIVE_CLEANUP=false
PRESERVE_DAYS=7
PRESERVE_RUNNING_ONLY=false
DRY_RUN=false
FORCE=false
VERBOSE=false
GENERATE_REPORT=false
CLEANUP_ALL=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --docker-system)
            CLEANUP_DOCKER_SYSTEM=true
            CLEANUP_ALL=false
            shift
            ;;
        --docker-images)
            CLEANUP_DOCKER_IMAGES=true
            CLEANUP_ALL=false
            shift
            ;;
        --docker-containers)
            CLEANUP_DOCKER_CONTAINERS=true
            CLEANUP_ALL=false
            shift
            ;;
        --docker-volumes)
            CLEANUP_DOCKER_VOLUMES=true
            CLEANUP_ALL=false
            shift
            ;;
        --docker-networks)
            CLEANUP_DOCKER_NETWORKS=true
            CLEANUP_ALL=false
            shift
            ;;
        --logs)
            CLEANUP_LOGS=true
            CLEANUP_ALL=false
            shift
            ;;
        --project-logs)
            CLEANUP_PROJECT_LOGS=true
            CLEANUP_ALL=false
            shift
            ;;
        --service-logs)
            CLEANUP_SERVICE_LOGS=true
            CLEANUP_ALL=false
            shift
            ;;
        --temp-files)
            CLEANUP_TEMP_FILES=true
            CLEANUP_ALL=false
            shift
            ;;
        --backup-cleanup)
            CLEANUP_BACKUPS=true
            CLEANUP_ALL=false
            shift
            ;;
        --aggressive)
            AGGRESSIVE_CLEANUP=true
            shift
            ;;
        --preserve-days)
            PRESERVE_DAYS="$2"
            shift 2
            ;;
        --preserve-running)
            PRESERVE_RUNNING_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        --all)
            CLEANUP_ALL=true
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
    
    # Set defaults from configuration
    BACKUP_BASE_PATH=${BACKUP_BASE_PATH:-/volume1/docker/backups}
    BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
    LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-7}
}

# Enhanced logging with verbose mode
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        log_info "VERBOSE: $1"
    fi
}

# Get current disk usage
get_disk_usage() {
    local path="$1"
    if [ -d "$path" ]; then
        du -sh "$path" 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

# Confirm action (unless forced)
confirm_action() {
    local message="$1"
    
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo -n "$message (y/N): "
    read -r response
    case $response in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Clean Docker containers
cleanup_docker_containers() {
    if [ "$CLEANUP_DOCKER_CONTAINERS" = false ] && [ "$CLEANUP_ALL" = false ] && [ "$CLEANUP_DOCKER_SYSTEM" = false ]; then
        return 0
    fi
    
    log_step "Cleaning Docker containers..."
    
    # Get stopped containers
    local stopped_containers=$(docker ps -aq --filter "status=exited")
    
    if [ -n "$stopped_containers" ]; then
        local container_count=$(echo "$stopped_containers" | wc -l)
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would remove $container_count stopped containers"
            verbose_log "Containers: $(echo "$stopped_containers" | tr '\n' ' ')"
        else
            if confirm_action "Remove $container_count stopped containers?"; then
                docker rm $stopped_containers
                log_success "Removed $container_count stopped containers"
            else
                log_info "Skipped container cleanup"
            fi
        fi
    else
        log_success "No stopped containers to clean"
    fi
    
    # Clean containers with dead status if aggressive mode
    if [ "$AGGRESSIVE_CLEANUP" = true ]; then
        local dead_containers=$(docker ps -aq --filter "status=dead")
        if [ -n "$dead_containers" ]; then
            local dead_count=$(echo "$dead_containers" | wc -l)
            
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would remove $dead_count dead containers"
            else
                if confirm_action "Remove $dead_count dead containers?"; then
                    docker rm $dead_containers
                    log_success "Removed $dead_count dead containers"
                fi
            fi
        fi
    fi
}

# Clean Docker images
cleanup_docker_images() {
    if [ "$CLEANUP_DOCKER_IMAGES" = false ] && [ "$CLEANUP_ALL" = false ] && [ "$CLEANUP_DOCKER_SYSTEM" = false ]; then
        return 0
    fi
    
    log_step "Cleaning Docker images..."
    
    # Get dangling images
    local dangling_images=$(docker images -qf "dangling=true")
    
    if [ -n "$dangling_images" ]; then
        local image_count=$(echo "$dangling_images" | wc -l)
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would remove $image_count dangling images"
        else
            if confirm_action "Remove $image_count dangling images?"; then
                docker rmi $dangling_images
                log_success "Removed $image_count dangling images"
            else
                log_info "Skipped dangling image cleanup"
            fi
        fi
    else
        log_success "No dangling images to clean"
    fi
    
    # Remove unused images if aggressive mode
    if [ "$AGGRESSIVE_CLEANUP" = true ]; then
        local unused_images=""
        
        if [ "$PRESERVE_RUNNING_ONLY" = true ]; then
            # Get images not used by running containers
            local used_images=$(docker ps --format "table {{.Image}}" | tail -n +2 | sort | uniq)
            local all_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
            
            for image in $all_images; do
                if ! echo "$used_images" | grep -q "^$image$"; then
                    unused_images="$unused_images $image"
                fi
            done
        fi
        
        if [ -n "$unused_images" ]; then
            local unused_count=$(echo "$unused_images" | wc -w)
            
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would remove $unused_count unused images"
                verbose_log "Images: $unused_images"
            else
                if confirm_action "Remove $unused_count unused images?"; then
                    docker rmi $unused_images 2>/dev/null || log_warning "Some images could not be removed (may be in use)"
                    log_success "Attempted to remove unused images"
                fi
            fi
        fi
    fi
}

# Clean Docker volumes
cleanup_docker_volumes() {
    if [ "$CLEANUP_DOCKER_VOLUMES" = false ] && [ "$CLEANUP_ALL" = false ] && [ "$CLEANUP_DOCKER_SYSTEM" = false ]; then
        return 0
    fi
    
    log_step "Cleaning Docker volumes..."
    
    # Get dangling volumes
    local dangling_volumes=$(docker volume ls -qf "dangling=true")
    
    if [ -n "$dangling_volumes" ]; then
        local volume_count=$(echo "$dangling_volumes" | wc -l)
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would remove $volume_count dangling volumes"
            verbose_log "Volumes: $(echo "$dangling_volumes" | tr '\n' ' ')"
        else
            if confirm_action "Remove $volume_count dangling volumes?"; then
                docker volume rm $dangling_volumes
                log_success "Removed $volume_count dangling volumes"
            else
                log_info "Skipped volume cleanup"
            fi
        fi
    else
        log_success "No dangling volumes to clean"
    fi
}

# Clean Docker networks
cleanup_docker_networks() {
    if [ "$CLEANUP_DOCKER_NETWORKS" = false ] && [ "$CLEANUP_ALL" = false ] && [ "$CLEANUP_DOCKER_SYSTEM" = false ]; then
        return 0
    fi
    
    log_step "Cleaning Docker networks..."
    
    # Get unused networks (excluding default networks)
    local unused_networks=$(docker network ls --filter "type=custom" -q)
    local networks_to_remove=""
    
    for network in $unused_networks; do
        local network_name=$(docker network inspect "$network" --format '{{.Name}}' 2>/dev/null)
        local containers_count=$(docker network inspect "$network" --format '{{len .Containers}}' 2>/dev/null || echo "0")
        
        # Skip default networks and networks with containers
        if [ "$containers_count" -eq 0 ] && [ "$network_name" != "bridge" ] && [ "$network_name" != "host" ] && [ "$network_name" != "none" ]; then
            networks_to_remove="$networks_to_remove $network"
        fi
    done
    
    if [ -n "$networks_to_remove" ]; then
        local network_count=$(echo "$networks_to_remove" | wc -w)
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would remove $network_count unused networks"
            verbose_log "Networks: $networks_to_remove"
        else
            if confirm_action "Remove $network_count unused networks?"; then
                docker network rm $networks_to_remove 2>/dev/null || log_warning "Some networks could not be removed"
                log_success "Cleaned unused networks"
            else
                log_info "Skipped network cleanup"
            fi
        fi
    else
        log_success "No unused networks to clean"
    fi
}

# Docker system prune
cleanup_docker_system() {
    if [ "$CLEANUP_DOCKER_SYSTEM" = false ] && [ "$CLEANUP_ALL" = false ]; then
        return 0
    fi
    
    log_step "Performing Docker system cleanup..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would perform Docker system prune"
        # Show what would be removed
        docker system df
        return 0
    fi
    
    local prune_args=""
    if [ "$AGGRESSIVE_CLEANUP" = true ]; then
        prune_args="--all"
        if confirm_action "Perform aggressive Docker system prune (removes all unused resources)?"; then
            local cleanup_output=$(docker system prune $prune_args --force 2>&1)
            log_success "Docker system prune completed"
            verbose_log "$cleanup_output"
        else
            log_info "Skipped aggressive Docker system prune"
        fi
    else
        if confirm_action "Perform Docker system prune (removes dangling resources)?"; then
            local cleanup_output=$(docker system prune --force 2>&1)
            log_success "Docker system prune completed"
            verbose_log "$cleanup_output"
        else
            log_info "Skipped Docker system prune"
        fi
    fi
}

# Clean project logs
cleanup_project_logs() {
    if [ "$CLEANUP_PROJECT_LOGS" = false ] && [ "$CLEANUP_LOGS" = false ] && [ "$CLEANUP_ALL" = false ]; then
        return 0
    fi
    
    log_step "Cleaning project logs..."
    
    local logs_dir="$PROJECT_ROOT/logs"
    
    if [ ! -d "$logs_dir" ]; then
        log_success "No project logs directory to clean"
        return 0
    fi
    
    # Find log files older than preserve days
    local old_logs=$(find "$logs_dir" -type f -name "*.log" -mtime +$PRESERVE_DAYS 2>/dev/null || true)
    
    if [ -n "$old_logs" ]; then
        local log_count=$(echo "$old_logs" | wc -l)
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would remove $log_count old log files"
            verbose_log "Logs: $(echo "$old_logs" | tr '\n' ' ')"
        else
            if confirm_action "Remove $log_count old log files (older than $PRESERVE_DAYS days)?"; then
                echo "$old_logs" | xargs rm -f
                log_success "Removed $log_count old log files"
            else
                log_info "Skipped project log cleanup"
            fi
        fi
    else
        log_success "No old project log files to clean"
    fi
    
    # Clean empty log directories
    find "$logs_dir" -type d -empty -delete 2>/dev/null || true
}

# Clean service logs
cleanup_service_logs() {
    if [ "$CLEANUP_SERVICE_LOGS" = false ] && [ "$CLEANUP_LOGS" = false ] && [ "$CLEANUP_ALL" = false ]; then
        return 0
    fi
    
    log_step "Cleaning service logs..."
    
    # Find all service directories
    local services=$(find "$COMPOSITIONS_DIR" -name "docker-compose.yml" -exec dirname {} \; 2>/dev/null)
    
    local cleaned_services=0
    
    for service_dir in $services; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        # Look for log files and directories in service directory
        local service_logs=$(find "$service_dir" -name "*.log" -o -name "logs" -type d 2>/dev/null || true)
        
        if [ -n "$service_logs" ]; then
            verbose_log "Found logs in $category/$service_name"
            
            # Clean old log files
            local old_service_logs=$(find "$service_dir" -name "*.log" -mtime +$PRESERVE_DAYS 2>/dev/null || true)
            
            if [ -n "$old_service_logs" ]; then
                local service_log_count=$(echo "$old_service_logs" | wc -l)
                
                if [ "$DRY_RUN" = true ]; then
                    log_info "DRY RUN: Would clean $service_log_count log files from $category/$service_name"
                else
                    echo "$old_service_logs" | xargs rm -f 2>/dev/null || true
                    ((cleaned_services++))
                fi
            fi
        fi
    done
    
    if [ "$cleaned_services" -gt 0 ]; then
        log_success "Cleaned logs from $cleaned_services services"
    else
        log_success "No old service logs to clean"
    fi
}

# Clean temporary files
cleanup_temp_files() {
    if [ "$CLEANUP_TEMP_FILES" = false ] && [ "$CLEANUP_ALL" = false ]; then
        return 0
    fi
    
    log_step "Cleaning temporary files..."
    
    local temp_patterns=(
        "$PROJECT_ROOT/**/*.tmp"
        "$PROJECT_ROOT/**/*.temp"
        "$PROJECT_ROOT/**/*~"
        "$PROJECT_ROOT/**/.DS_Store"
        "$PROJECT_ROOT/**/Thumbs.db"
        "/tmp/docker-*"
    )
    
    local cleaned_files=0
    
    for pattern in "${temp_patterns[@]}"; do
        local temp_files=$(find $(dirname "$pattern") -name "$(basename "$pattern")" -type f -mtime +1 2>/dev/null || true)
        
        if [ -n "$temp_files" ]; then
            local file_count=$(echo "$temp_files" | wc -l)
            
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would remove $file_count temporary files matching $pattern"
            else
                echo "$temp_files" | xargs rm -f 2>/dev/null || true
                cleaned_files=$((cleaned_files + file_count))
            fi
        fi
    done
    
    if [ "$cleaned_files" -gt 0 ]; then
        log_success "Removed $cleaned_files temporary files"
    else
        log_success "No temporary files to clean"
    fi
}

# Clean old backups
cleanup_old_backups() {
    if [ "$CLEANUP_BACKUPS" = false ] && [ "$CLEANUP_ALL" = false ]; then
        return 0
    fi
    
    log_step "Cleaning old backups..."
    
    if [ ! -d "$BACKUP_BASE_PATH" ]; then
        log_success "No backup directory to clean"
        return 0
    fi
    
    local retention_days=${BACKUP_RETENTION_DAYS:-$PRESERVE_DAYS}
    
    # Find old backup files
    local old_backups=$(find "$BACKUP_BASE_PATH" -type f -name "*.tar.gz" -mtime +$retention_days 2>/dev/null || true)
    local old_backup_dirs=$(find "$BACKUP_BASE_PATH" -type d -mtime +$retention_days -mindepth 1 2>/dev/null || true)
    
    local backup_files_count=0
    local backup_dirs_count=0
    
    if [ -n "$old_backups" ]; then
        backup_files_count=$(echo "$old_backups" | wc -l)
    fi
    
    if [ -n "$old_backup_dirs" ]; then
        backup_dirs_count=$(echo "$old_backup_dirs" | wc -l)
    fi
    
    local total_backups=$((backup_files_count + backup_dirs_count))
    
    if [ "$total_backups" -gt 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would remove $total_backups old backups (older than $retention_days days)"
            verbose_log "Files: $backup_files_count, Directories: $backup_dirs_count"
        else
            if confirm_action "Remove $total_backups old backups (older than $retention_days days)?"; then
                [ -n "$old_backups" ] && echo "$old_backups" | xargs rm -f 2>/dev/null || true
                [ -n "$old_backup_dirs" ] && echo "$old_backup_dirs" | xargs rm -rf 2>/dev/null || true
                log_success "Removed $total_backups old backups"
            else
                log_info "Skipped backup cleanup"
            fi
        fi
    else
        log_success "No old backups to clean"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    if [ "$GENERATE_REPORT" = false ]; then
        return 0
    fi
    
    log_step "Generating cleanup report..."
    
    local report_file="$PROJECT_ROOT/logs/cleanup-report-$CLEANUP_DATE.txt"
    
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
Docker Management Cleanup Report
================================
Generated: $(date)
Host: $(hostname)

Cleanup Configuration:
- Preserve Days: $PRESERVE_DAYS
- Aggressive Mode: $AGGRESSIVE_CLEANUP
- Dry Run: $DRY_RUN
- Force Mode: $FORCE

Summary:
- Items Cleaned: $CLEANUP_ITEMS
- Errors: $CLEANUP_ERRORS
- Space Freed: $CLEANUP_SPACE_FREED

Operations Performed:
- Docker Containers: $([ "$CLEANUP_DOCKER_CONTAINERS" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")
- Docker Images: $([ "$CLEANUP_DOCKER_IMAGES" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")  
- Docker Volumes: $([ "$CLEANUP_DOCKER_VOLUMES" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")
- Docker Networks: $([ "$CLEANUP_DOCKER_NETWORKS" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")
- Docker System: $([ "$CLEANUP_DOCKER_SYSTEM" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")
- Project Logs: $([ "$CLEANUP_PROJECT_LOGS" = true ] || [ "$CLEANUP_LOGS" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")
- Service Logs: $([ "$CLEANUP_SERVICE_LOGS" = true ] || [ "$CLEANUP_LOGS" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")
- Temporary Files: $([ "$CLEANUP_TEMP_FILES" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")
- Old Backups: $([ "$CLEANUP_BACKUPS" = true ] || [ "$CLEANUP_ALL" = true ] && echo "Yes" || echo "No")

System Status After Cleanup:
- Docker Images: $(docker images | wc -l) total
- Docker Containers: $(docker ps -a | wc -l) total
- Docker Volumes: $(docker volume ls | wc -l) total
- Docker Networks: $(docker network ls | wc -l) total

EOF
    
    log_success "Cleanup report generated: $report_file"
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    echo "========================================"
    echo "         Cleanup Summary"
    echo "========================================"
    echo ""
    
    echo "Cleanup Results:"
    echo "  Items Processed: $CLEANUP_ITEMS"
    echo "  Errors: $CLEANUP_ERRORS"
    echo "  Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "EXECUTED")"
    echo "  Aggressive: $([ "$AGGRESSIVE_CLEANUP" = true ] && echo "Yes" || echo "No")"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        echo "Space Usage After Cleanup:"
        echo "  Docker System: $(docker system df --format "table {{.Type}}\t{{.Size}}" 2>/dev/null | tail -n +2 | awk '{sum+=$2} END {print sum "B"}' || echo "Unknown")"
        echo "  Project Directory: $(get_disk_usage "$PROJECT_ROOT")"
        echo ""
    fi
    
    echo "Recommendations:"
    echo "  - Run cleanup regularly to maintain system performance"
    echo "  - Monitor disk usage: df -h"
    echo "  - Check Docker system usage: docker system df"
    echo "  - Review backup retention policies"
    echo ""
    
    echo "Next Steps:"
    echo "  - Health check: docker/scripts/health-check.sh"
    echo "  - System monitoring: docker/scripts/monitor.sh"
    echo "  - Backup important data: docker/scripts/backup-all.sh"
    echo ""
}

# Main execution
main() {
    echo "========================================"
    echo "     Docker System Cleanup Script"
    echo "========================================"
    echo ""
    
    cd "$PROJECT_ROOT"
    load_global_config
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    # Show current disk usage
    log_info "Current system status:"
    echo "  Project directory: $(get_disk_usage "$PROJECT_ROOT")"
    echo "  Docker system usage:"
    docker system df 2>/dev/null || log_warning "Could not get Docker system usage"
    echo ""
    
    # Perform cleanup operations
    cleanup_docker_containers
    cleanup_docker_images
    cleanup_docker_volumes
    cleanup_docker_networks
    cleanup_docker_system
    cleanup_project_logs
    cleanup_service_logs
    cleanup_temp_files
    cleanup_old_backups
    
    # Generate report and summary
    generate_cleanup_report
    show_cleanup_summary
    
    if [ "$DRY_RUN" = false ]; then
        if [ "$CLEANUP_ERRORS" -eq 0 ]; then
            log_success "Cleanup completed successfully!"
        else
            log_warning "Cleanup completed with $CLEANUP_ERRORS errors"
        fi
    else
        log_info "DRY RUN completed - no changes were made"
    fi
}

# Error handling
trap 'log_error "Cleanup script failed on line $LINENO"' ERR

# Execute main function
main "$@"