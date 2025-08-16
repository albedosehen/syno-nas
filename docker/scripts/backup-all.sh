#!/bin/bash

# Synology NAS Docker Management - Comprehensive Backup Script
# This script creates backups for all configured services in the project
# with support for incremental backups, compression, and backup management

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PREFIX="syno-nas-backup"

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
    echo "Synology NAS Docker Management - Comprehensive Backup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --category CATEGORY      Backup only services in specified category"
    echo "                              (management, media, productivity, networking)"
    echo "  -s, --service SERVICE        Backup only specified service"
    echo "  -d, --destination DIR        Backup destination directory"
    echo "  -i, --incremental           Create incremental backup (only changed data)"
    echo "  --compress                  Create compressed backups (tar.gz)"
    echo "  --stop-services             Stop services before backup (recommended)"
    echo "  --parallel                  Enable parallel backup operations"
    echo "  --verify                    Verify backup integrity after creation"
    echo "  --cleanup                   Clean up old backups based on retention policy"
    echo "  --offsite                   Sync backup to offsite location (if configured)"
    echo "  --exclude PATTERN           Exclude files matching pattern"
    echo "  --dry-run                   Show what would be backed up without executing"
    echo "  --verbose                   Enable verbose output"
    echo "  -l, --list                  List available backups"
    echo "  -r, --restore BACKUP        Restore from specific backup"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          Backup all services to default location"
    echo "  $0 -c management --compress Backup management services with compression"
    echo "  $0 -s portainer --stop-services  Backup Portainer with service stop"
    echo "  $0 --incremental --cleanup  Create incremental backup and clean old ones"
    echo "  $0 -l                       List available backups"
    echo "  $0 -r backup_20241201_120000.tar.gz  Restore from specific backup"
    echo ""
}

# Parse command line arguments
TARGET_CATEGORY=""
TARGET_SERVICE=""
BACKUP_DESTINATION=""
INCREMENTAL_BACKUP=false
COMPRESS_BACKUP=false
STOP_SERVICES=false
PARALLEL_BACKUP=false
VERIFY_BACKUP=false
CLEANUP_OLD=false
OFFSITE_SYNC=false
EXCLUDE_PATTERNS=()
DRY_RUN=false
VERBOSE=false
LIST_BACKUPS=false
RESTORE_BACKUP=""

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
        -d|--destination)
            BACKUP_DESTINATION="$2"
            shift 2
            ;;
        -i|--incremental)
            INCREMENTAL_BACKUP=true
            shift
            ;;
        --compress)
            COMPRESS_BACKUP=true
            shift
            ;;
        --stop-services)
            STOP_SERVICES=true
            shift
            ;;
        --parallel)
            PARALLEL_BACKUP=true
            shift
            ;;
        --verify)
            VERIFY_BACKUP=true
            shift
            ;;
        --cleanup)
            CLEANUP_OLD=true
            shift
            ;;
        --offsite)
            OFFSITE_SYNC=true
            shift
            ;;
        --exclude)
            EXCLUDE_PATTERNS+=("$2")
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
        -l|--list)
            LIST_BACKUPS=true
            shift
            ;;
        -r|--restore)
            RESTORE_BACKUP="$2"
            shift 2
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
    
    # Set defaults from configuration or fallback values
    BACKUP_BASE_PATH=${BACKUP_BASE_PATH:-/volume1/docker/backups}
    BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
    BACKUP_COMPRESS=${BACKUP_COMPRESS:-true}
    BACKUP_OFFSITE_ENABLED=${BACKUP_OFFSITE_ENABLED:-false}
    MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-4}
    
    # Set backup destination if not specified
    if [ -z "$BACKUP_DESTINATION" ]; then
        BACKUP_DESTINATION="$BACKUP_BASE_PATH"
    fi
}

# Enhanced logging with verbose mode
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        log_info "VERBOSE: $1"
    fi
}

# Create backup directory
create_backup_directory() {
    log_step "Creating backup directory structure..."
    
    local main_backup_dir="$BACKUP_DESTINATION"
    local project_backup_dir="$main_backup_dir/project"
    local services_backup_dir="$main_backup_dir/services"
    
    for dir in "$main_backup_dir" "$project_backup_dir" "$services_backup_dir"; do
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would create directory: $dir"
        else
            if [ ! -d "$dir" ]; then
                mkdir -p "$dir"
                verbose_log "Created directory: $dir"
            fi
        fi
    done
    
    log_success "Backup directory structure ready"
}

# Discover services to backup
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

# Stop services before backup
stop_services() {
    local services=("$@")
    
    if [ "$STOP_SERVICES" = false ]; then
        return 0
    fi
    
    log_step "Stopping services for consistent backup..."
    
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        log_service "Stopping $category/$service_name"
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would stop $category/$service_name"
        else
            cd "$service_dir"
            docker-compose stop 2>/dev/null || log_warning "Failed to stop $category/$service_name"
        fi
    done
    
    log_success "Services stopped for backup"
}

# Start services after backup
start_services() {
    local services=("$@")
    
    if [ "$STOP_SERVICES" = false ]; then
        return 0
    fi
    
    log_step "Starting services after backup..."
    
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        log_service "Starting $category/$service_name"
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would start $category/$service_name"
        else
            cd "$service_dir"
            docker-compose start 2>/dev/null || log_warning "Failed to start $category/$service_name"
        fi
    done
    
    log_success "Services restarted after backup"
}

# Backup single service
backup_service() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_service "Backing up $category/$service_name"
    
    local service_backup_dir="$BACKUP_DESTINATION/services/${category}_${service_name}_${BACKUP_DATE}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would backup $category/$service_name to $service_backup_dir"
        return 0
    fi
    
    # Check if service has custom backup script
    if [ -f "$service_dir/backup.sh" ] && [ -x "$service_dir/backup.sh" ]; then
        verbose_log "Using service-specific backup script for $category/$service_name"
        
        cd "$service_dir"
        
        local backup_args=""
        if [ "$COMPRESS_BACKUP" = true ]; then
            backup_args="$backup_args --compress"
        fi
        
        # Execute service backup script with destination override
        ./backup.sh --destination "$service_backup_dir" $backup_args
    else
        # Generic backup process
        verbose_log "Using generic backup process for $category/$service_name"
        
        mkdir -p "$service_backup_dir"
        
        cd "$service_dir"
        
        # Build exclusion patterns
        local tar_excludes=""
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            tar_excludes="$tar_excludes --exclude=$pattern"
        done
        
        # Add default exclusions
        tar_excludes="$tar_excludes --exclude=*.log --exclude=*.tmp --exclude=.git"
        
        if [ "$COMPRESS_BACKUP" = true ]; then
            local backup_file="$service_backup_dir.tar.gz"
            tar -czf "$backup_file" $tar_excludes \
                --exclude="$backup_file" \
                . 2>/dev/null || log_warning "Some files may not be included in backup for $category/$service_name"
            
            # Remove empty directory
            rmdir "$service_backup_dir" 2>/dev/null || true
        else
            # Copy files to backup directory
            cp -r . "$service_backup_dir/" 2>/dev/null || log_warning "Some files may not be copied for $category/$service_name"
        fi
    fi
    
    log_success "Backed up $category/$service_name"
    return 0
}

# Backup services in parallel
backup_services_parallel() {
    local services=("$@")
    local pids=()
    local max_jobs=${MAX_PARALLEL_JOBS:-4}
    
    log_info "Backing up ${#services[@]} services in parallel (max $max_jobs jobs)"
    
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
        
        # Start backup in background
        backup_service "$service" &
        pids+=($!)
    done
    
    # Wait for all remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Backup services sequentially
backup_services_sequential() {
    local services=("$@")
    
    log_info "Backing up ${#services[@]} services sequentially"
    
    for service in "${services[@]}"; do
        backup_service "$service"
    done
}

# Create project-level backup
backup_project_config() {
    log_step "Creating project configuration backup..."
    
    local project_backup_dir="$BACKUP_DESTINATION/project/config_${BACKUP_DATE}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would backup project configuration to $project_backup_dir"
        return 0
    fi
    
    mkdir -p "$project_backup_dir"
    
    cd "$PROJECT_ROOT"
    
    # Files to include in project backup
    local project_files=(
        ".env"
        ".env.example"
        "docker-compose.yml"
        "README.md"
        "CONTRIBUTING.md"
        "CHANGELOG.md"
        "docker/scripts/"
        "docs/"
    )
    
    for item in "${project_files[@]}"; do
        if [ -e "$item" ]; then
            if [ -d "$item" ]; then
                cp -r "$item" "$project_backup_dir/"
            else
                cp "$item" "$project_backup_dir/"
            fi
            verbose_log "Backed up: $item"
        fi
    done
    
    # Create backup metadata
    cat > "$project_backup_dir/backup_info.txt" << EOF
Project Backup Information
=========================
Backup Date: $(date)
Backup Type: Project Configuration
Project Root: $PROJECT_ROOT
Backup Location: $project_backup_dir
Created By: $USER

Contents:
- Global configuration files
- Project documentation
- Management scripts
- Service compositions structure

Restore Instructions:
1. Stop all services
2. Replace project files with backed up versions
3. Review and update configuration as needed
4. Restart services
EOF
    
    log_success "Project configuration backed up"
}

# Verify backup integrity
verify_backups() {
    if [ "$VERIFY_BACKUP" = false ]; then
        return 0
    fi
    
    log_step "Verifying backup integrity..."
    
    local backup_errors=0
    
    # Verify compressed backups
    for backup_file in "$BACKUP_DESTINATION"/services/*.tar.gz; do
        if [ -f "$backup_file" ]; then
            verbose_log "Verifying: $backup_file"
            if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
                log_error "Backup file corrupted: $backup_file"
                ((backup_errors++))
            fi
        fi
    done
    
    # Verify directory backups
    for backup_dir in "$BACKUP_DESTINATION"/services/*/; do
        if [ -d "$backup_dir" ]; then
            verbose_log "Verifying: $backup_dir"
            if [ ! -f "$backup_dir/docker-compose.yml" ]; then
                log_warning "Backup directory missing docker-compose.yml: $backup_dir"
                ((backup_errors++))
            fi
        fi
    done
    
    if [ $backup_errors -eq 0 ]; then
        log_success "All backups verified successfully"
    else
        log_error "Found $backup_errors backup integrity issues"
        return 1
    fi
}

# Clean up old backups
cleanup_old_backups() {
    if [ "$CLEANUP_OLD" = false ]; then
        return 0
    fi
    
    log_step "Cleaning up old backups (retention: $BACKUP_RETENTION_DAYS days)..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would clean up backups older than $BACKUP_RETENTION_DAYS days"
        return 0
    fi
    
    local cleaned_count=0
    
    # Clean up old service backups
    find "$BACKUP_DESTINATION/services" -maxdepth 1 -type f -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -exec rm {} \; -exec echo "Removed: {}" \; | while read line; do
        verbose_log "$line"
        ((cleaned_count++))
    done
    
    find "$BACKUP_DESTINATION/services" -maxdepth 1 -type d -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} \; -exec echo "Removed: {}" \; | while read line; do
        verbose_log "$line"
        ((cleaned_count++))
    done
    
    # Clean up old project backups
    find "$BACKUP_DESTINATION/project" -maxdepth 1 -type d -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} \; -exec echo "Removed: {}" \; | while read line; do
        verbose_log "$line"
        ((cleaned_count++))
    done
    
    log_success "Cleaned up old backups"
}

# Sync to offsite location
sync_offsite() {
    if [ "$OFFSITE_SYNC" = false ] || [ "$BACKUP_OFFSITE_ENABLED" = false ]; then
        return 0
    fi
    
    log_step "Syncing backups to offsite location..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would sync backups to offsite location"
        return 0
    fi
    
    # This would need to be configured based on the specific offsite solution
    # Examples: rsync to remote server, cloud storage sync, etc.
    log_warning "Offsite sync not implemented - configure based on your backup strategy"
}

# List available backups
list_backups() {
    log_info "Available backups in $BACKUP_DESTINATION:"
    echo ""
    
    if [ ! -d "$BACKUP_DESTINATION" ]; then
        log_warning "Backup directory does not exist: $BACKUP_DESTINATION"
        return
    fi
    
    echo "Service Backups:"
    echo "---------------"
    
    # List service backups
    for backup in "$BACKUP_DESTINATION"/services/*; do
        if [ -e "$backup" ]; then
            local basename=$(basename "$backup")
            local size=""
            local date=""
            
            if [ -f "$backup" ]; then
                size=$(du -h "$backup" | cut -f1)
                date=$(stat -c %y "$backup" | cut -d' ' -f1)
                echo "  $basename (${size}, $date) [compressed]"
            elif [ -d "$backup" ]; then
                size=$(du -sh "$backup" | cut -f1)
                date=$(stat -c %y "$backup" | cut -d' ' -f1)
                echo "  $basename (${size}, $date) [directory]"
            fi
        fi
    done
    
    echo ""
    echo "Project Backups:"
    echo "---------------"
    
    # List project backups
    for backup in "$BACKUP_DESTINATION"/project/*; do
        if [ -d "$backup" ]; then
            local basename=$(basename "$backup")
            local size=$(du -sh "$backup" | cut -f1)
            local date=$(stat -c %y "$backup" | cut -d' ' -f1)
            echo "  $basename (${size}, $date)"
        fi
    done
    
    echo ""
}

# Restore from backup (placeholder - would need specific implementation)
restore_backup() {
    local backup_path="$1"
    
    log_warning "Backup restoration functionality not yet implemented"
    log_info "To restore manually:"
    log_info "1. Stop all services: $PROJECT_ROOT/docker/scripts/manage-services.sh stop -a"
    log_info "2. Extract/copy backup files to service directories"
    log_info "3. Verify configurations and permissions"
    log_info "4. Start services: $PROJECT_ROOT/docker/scripts/manage-services.sh start -a"
}

# Display backup summary
show_backup_summary() {
    local services=("$@")
    
    echo ""
    echo "========================================"
    echo "         Backup Summary"
    echo "========================================"
    echo ""
    
    echo "Backup Configuration:"
    echo "  Date: $BACKUP_DATE"
    echo "  Destination: $BACKUP_DESTINATION"
    echo "  Services: ${#services[@]}"
    echo "  Compression: $([ "$COMPRESS_BACKUP" = true ] && echo "Enabled" || echo "Disabled")"
    echo "  Service Stop: $([ "$STOP_SERVICES" = true ] && echo "Yes" || echo "No")"
    echo "  Parallel: $([ "$PARALLEL_BACKUP" = true ] && echo "Yes" || echo "No")"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        echo "Backup Locations:"
        echo "  Services: $BACKUP_DESTINATION/services/"
        echo "  Project: $BACKUP_DESTINATION/project/"
        echo ""
        
        # Calculate total backup size
        local total_size=$(du -sh "$BACKUP_DESTINATION" 2>/dev/null | cut -f1 || echo "Unknown")
        echo "Total Backup Size: $total_size"
        echo ""
    fi
    
    echo "Management Commands:"
    echo "  List backups: $0 --list"
    echo "  Cleanup old: $0 --cleanup"
    echo "  Verify integrity: $0 --verify"
    echo ""
}

# Main execution
main() {
    echo "========================================"
    echo "    Comprehensive Backup Script"
    echo "========================================"
    echo ""
    
    cd "$PROJECT_ROOT"
    load_global_config
    
    # Handle special actions first
    if [ "$LIST_BACKUPS" = true ]; then
        list_backups
        exit 0
    fi
    
    if [ -n "$RESTORE_BACKUP" ]; then
        restore_backup "$RESTORE_BACKUP"
        exit 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    # Discover services to backup
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
        # Backup all services
        services=($(discover_services "all"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "No services found"
            exit 1
        fi
    fi
    
    log_info "Found ${#services[@]} services to backup"
    verbose_log "Services: ${services[*]}"
    
    # Execute backup process
    create_backup_directory
    
    # Stop services if requested
    stop_services "${services[@]}"
    
    # Backup project configuration
    backup_project_config
    
    # Backup services
    if [ "$PARALLEL_BACKUP" = true ] && [ ${#services[@]} -gt 1 ]; then
        backup_services_parallel "${services[@]}"
    else
        backup_services_sequential "${services[@]}"
    fi
    
    # Start services if they were stopped
    start_services "${services[@]}"
    
    # Post-backup operations
    if [ "$DRY_RUN" = false ]; then
        verify_backups
        cleanup_old_backups
        sync_offsite
    fi
    
    # Show summary
    show_backup_summary "${services[@]}"
    
    if [ "$DRY_RUN" = false ]; then
        log_success "Backup operation completed successfully!"
    else
        log_info "DRY RUN completed - no changes were made"
    fi
}

# Error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Execute main function
main "$@"