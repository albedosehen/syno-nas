#!/bin/bash

# Portainer Backup Script for Synology NAS
# This script creates backups of Portainer data and configuration

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PREFIX="portainer_backup"
DEFAULT_BACKUP_DIR="/volume1/docker/backups/portainer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Help function
show_help() {
    echo "Portainer Backup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --destination DIR    Backup destination directory (default: $DEFAULT_BACKUP_DIR)"
    echo "  -s, --stop-service       Stop Portainer service before backup (recommended)"
    echo "  -c, --compress           Create compressed backup (tar.gz)"
    echo "  -r, --restore FILE       Restore from backup file"
    echo "  -l, --list               List available backups"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                       Create backup with default settings"
    echo "  $0 -s -c                 Stop service and create compressed backup"
    echo "  $0 -d /custom/path       Backup to custom directory"
    echo "  $0 -r backup.tar.gz      Restore from backup file"
    echo "  $0 -l                    List available backups"
    echo ""
}

# Parse command line arguments
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
STOP_SERVICE=false
COMPRESS=false
RESTORE_FILE=""
LIST_BACKUPS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--destination)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -s|--stop-service)
            STOP_SERVICE=true
            shift
            ;;
        -c|--compress)
            COMPRESS=true
            shift
            ;;
        -r|--restore)
            RESTORE_FILE="$2"
            shift 2
            ;;
        -l|--list)
            LIST_BACKUPS=true
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

# Check if running as correct user
check_permissions() {
    if [ ! -w "$SCRIPT_DIR" ]; then
        log_error "No write permission in script directory"
        log_info "You may need to run this script with appropriate permissions"
        exit 1
    fi
}

# Create backup directory
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_info "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR" || {
            log_error "Failed to create backup directory"
            exit 1
        }
    fi
}

# Stop Portainer service
stop_service() {
    if [ "$STOP_SERVICE" = true ]; then
        log_info "Stopping Portainer service..."
        cd "$SCRIPT_DIR"
        if docker-compose ps | grep -q "Up"; then
            docker-compose stop portainer
            log_success "Portainer service stopped"
            return 0
        else
            log_warning "Portainer service is not running"
            return 1
        fi
    fi
    return 1
}

# Start Portainer service
start_service() {
    if [ "$1" = true ]; then
        log_info "Starting Portainer service..."
        cd "$SCRIPT_DIR"
        docker-compose start portainer
        log_success "Portainer service started"
    fi
}

# Create backup
create_backup() {
    log_info "Creating Portainer backup..."
    
    cd "$SCRIPT_DIR"
    
    # Source environment variables
    if [ -f ".env" ]; then
        source .env
    fi
    
    local service_was_stopped
    service_was_stopped=$(stop_service && echo true || echo false)
    
    # Create backup
    local backup_name="${BACKUP_PREFIX}_${BACKUP_DATE}"
    local backup_path
    
    if [ "$COMPRESS" = true ]; then
        backup_path="${BACKUP_DIR}/${backup_name}.tar.gz"
        log_info "Creating compressed backup: $backup_path"
        
        tar -czf "$backup_path" \
            --exclude='*.log' \
            --exclude='*.tmp' \
            data/ \
            docker-compose.yml \
            .env \
            .env.example \
            README.md \
            deploy.sh \
            backup.sh 2>/dev/null || log_warning "Some files may not be included in backup"
    else
        backup_path="${BACKUP_DIR}/${backup_name}"
        log_info "Creating directory backup: $backup_path"
        
        mkdir -p "$backup_path"
        
        # Copy files
        if [ -d "data" ]; then
            cp -r data "$backup_path/"
        fi
        
        cp docker-compose.yml "$backup_path/" 2>/dev/null || log_warning "docker-compose.yml not found"
        cp .env "$backup_path/" 2>/dev/null || log_warning ".env not found"
        cp .env.example "$backup_path/" 2>/dev/null || log_warning ".env.example not found"
        cp README.md "$backup_path/" 2>/dev/null || log_warning "README.md not found"
        cp deploy.sh "$backup_path/" 2>/dev/null || log_warning "deploy.sh not found"
        cp backup.sh "$backup_path/" 2>/dev/null || log_warning "backup.sh not found"
    fi
    
    # Restart service if it was stopped
    start_service "$service_was_stopped"
    
    # Verify backup
    if [ -e "$backup_path" ]; then
        local backup_size
        if [ "$COMPRESS" = true ]; then
            backup_size=$(du -h "$backup_path" | cut -f1)
        else
            backup_size=$(du -sh "$backup_path" | cut -f1)
        fi
        
        log_success "Backup created successfully"
        log_info "Backup location: $backup_path"
        log_info "Backup size: $backup_size"
        
        # Create backup info file
        local info_file="${backup_path%.*}.info"
        if [ "$COMPRESS" = true ]; then
            info_file="${backup_path%.tar.gz}.info"
        fi
        
        cat > "$info_file" << EOF
Portainer Backup Information
============================
Backup Date: $(date)
Backup Type: $([ "$COMPRESS" = true ] && echo "Compressed" || echo "Directory")
Service Stopped: $([ "$service_was_stopped" = true ] && echo "Yes" || echo "No")
Source Directory: $SCRIPT_DIR
Backup Size: $backup_size
Created By: $USER

Contents:
- Portainer data directory
- Docker Compose configuration
- Environment files
- Documentation
- Scripts

Restore Command:
$0 --restore "$backup_path"
EOF
        
        log_info "Backup info saved to: $info_file"
    else
        log_error "Backup creation failed"
        exit 1
    fi
}

# List backups
list_backups() {
    log_info "Available backups in $BACKUP_DIR:"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_warning "Backup directory does not exist: $BACKUP_DIR"
        return
    fi
    
    local found_backups=false
    
    # List compressed backups
    for backup in "$BACKUP_DIR"/${BACKUP_PREFIX}_*.tar.gz; do
        if [ -f "$backup" ]; then
            found_backups=true
            local size=$(du -h "$backup" | cut -f1)
            local date=$(stat -c %y "$backup" | cut -d' ' -f1)
            local basename=$(basename "$backup")
            printf "%-40s %8s %12s (compressed)\n" "$basename" "$size" "$date"
        fi
    done
    
    # List directory backups
    for backup in "$BACKUP_DIR"/${BACKUP_PREFIX}_*; do
        if [ -d "$backup" ]; then
            found_backups=true
            local size=$(du -sh "$backup" | cut -f1)
            local date=$(stat -c %y "$backup" | cut -d' ' -f1)
            local basename=$(basename "$backup")
            printf "%-40s %8s %12s (directory)\n" "$basename" "$size" "$date"
        fi
    done
    
    if [ "$found_backups" = false ]; then
        log_warning "No backups found"
    else
        echo ""
        log_info "Use --restore <backup_name> to restore from a backup"
    fi
}

# Restore from backup
restore_backup() {
    local restore_path="$1"
    
    log_info "Restoring Portainer from backup: $restore_path"
    
    # Check if backup exists
    if [ ! -e "$restore_path" ]; then
        log_error "Backup file/directory not found: $restore_path"
        exit 1
    fi
    
    cd "$SCRIPT_DIR"
    
    # Stop service
    local service_was_running=false
    if docker-compose ps | grep -q "Up"; then
        service_was_running=true
        log_info "Stopping Portainer service..."
        docker-compose stop portainer
    fi
    
    # Backup current data
    local current_backup="data.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -d "data" ]; then
        log_info "Backing up current data to: $current_backup"
        mv data "$current_backup"
    fi
    
    # Restore data
    if [[ "$restore_path" == *.tar.gz ]]; then
        log_info "Extracting compressed backup..."
        tar -xzf "$restore_path"
    else
        log_info "Copying from directory backup..."
        if [ -d "$restore_path/data" ]; then
            cp -r "$restore_path/data" ./
        fi
        
        # Optionally restore configuration files
        read -p "Do you want to restore configuration files (.env, docker-compose.yml)? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            [ -f "$restore_path/.env" ] && cp "$restore_path/.env" ./
            [ -f "$restore_path/docker-compose.yml" ] && cp "$restore_path/docker-compose.yml" ./
            log_info "Configuration files restored"
        fi
    fi
    
    # Set proper permissions
    if [ -d "data" ]; then
        # Source environment file to get PUID/PGID
        if [ -f ".env" ]; then
            source .env
        fi
        
        if [ -n "$PUID" ] && [ -n "$PGID" ]; then
            chown -R "$PUID:$PGID" data 2>/dev/null || log_warning "Could not set ownership"
        fi
        chmod -R 755 data
    fi
    
    # Start service if it was running
    if [ "$service_was_running" = true ]; then
        log_info "Starting Portainer service..."
        docker-compose start portainer
    fi
    
    log_success "Restore completed successfully"
    log_info "Previous data backed up to: $current_backup"
}

# Main execution
main() {
    echo "========================================"
    echo "     Portainer Backup Script"
    echo "========================================"
    echo ""
    
    cd "$SCRIPT_DIR"
    
    check_permissions
    
    if [ "$LIST_BACKUPS" = true ]; then
        list_backups
        exit 0
    fi
    
    if [ -n "$RESTORE_FILE" ]; then
        restore_backup "$RESTORE_FILE"
        exit 0
    fi
    
    create_backup_dir
    create_backup
    
    log_success "Backup operation completed successfully!"
}

# Execute main function
main