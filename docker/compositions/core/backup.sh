#!/bin/bash
set -euo pipefail

# ===========================================
# UNIFIED CORE SERVICES BACKUP SCRIPT
# ===========================================
# Automated backup script for Synology NAS DS1520+
# Services: Portainer, SurrealDB, Doppler
# Platform: Linux/Synology DSM 7.2+
#
# Usage: ./backup.sh [OPTIONS]
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
readonly LOG_FILE="${SCRIPT_DIR}/backup.log"
readonly DEFAULT_BACKUP_DIR="/volume1/docker/backups/core"

# Global variables
VERBOSE=false
DRY_RUN=false
AUTO_CONFIRM=false
ENCRYPT_BACKUP=false
COMPRESS_BACKUP=true
VERIFY_BACKUP=true
CLEANUP_OLD=true
RETENTION_DAYS=30
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
BACKUP_TYPE="full"
EXCLUDE_LOGS=false

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
    log_error "Backup script failed at line $line_number with exit code $exit_code"
    cleanup_temp_files
    exit $exit_code
}

trap 'handle_error ${LINENO}' ERR

# Cleanup function
cleanup_temp_files() {
    log_debug "Cleaning up temporary files..."
    find /tmp -name "core-backup-*" -type f -mmin +60 -delete 2>/dev/null || true
}

trap cleanup_temp_files EXIT

# Help function
show_help() {
    cat << EOF
${CYAN}Unified Core Services Backup Script${NC}

${YELLOW}USAGE:${NC}
    $0 [OPTIONS]

${YELLOW}DESCRIPTION:${NC}
    Creates automated backups of all unified core services data including
    Portainer configurations, SurrealDB databases, and environment settings.
    
    Supports compression, encryption, and automated retention management.
    Optimized for Synology NAS DS1520+ with DSM 7.2+

${YELLOW}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be backed up without creating backup
    -y, --yes               Auto-confirm all prompts
    -e, --encrypt           Encrypt backup files (requires passphrase)
    -c, --no-compress       Disable compression (faster but larger files)
    -n, --no-verify         Skip backup verification
    -k, --no-cleanup        Skip cleanup of old backups
    -r, --retention DAYS    Retention period in days (default: 30)
    -o, --output DIR        Custom backup directory (default: $DEFAULT_BACKUP_DIR)
    -t, --type TYPE         Backup type: full|data|config (default: full)
    -x, --exclude-logs      Exclude log files from backup
    
${YELLOW}BACKUP TYPES:${NC}
    full                    Complete backup including data, configs, and logs
    data                    Only service data (databases, persistent volumes)
    config                  Only configuration files (.env, docker-compose.yml)

${YELLOW}EXAMPLES:${NC}
    $0                      # Full backup with default settings
    $0 -v                   # Verbose full backup
    $0 -e                   # Encrypted backup (will prompt for passphrase)
    $0 -t data              # Backup only service data
    $0 -r 7                 # Keep backups for 7 days only
    $0 -o /mnt/external     # Backup to external drive
    $0 --dry-run            # Show what would be backed up

${YELLOW}BACKUP CONTENTS:${NC}
    • Portainer data and configurations
    • SurrealDB database files
    • Environment configuration (.env)
    • Docker Compose configuration
    • Service logs (unless excluded)
    • Backup metadata and checksums

${YELLOW}SECURITY FEATURES:${NC}
    • Optional GPG encryption for sensitive data
    • SHA256 checksums for integrity verification
    • Secure file permissions
    • No sensitive data in logs

${YELLOW}AUTOMATION:${NC}
    Add to crontab for automated backups:
    0 2 * * * /path/to/backup.sh -y >/dev/null 2>&1

    Or use DSM Task Scheduler:
    /volume1/docker/syno-nas/docker/compositions/core/backup.sh --yes

For more information, see README.md
EOF
}

# Prerequisites check
check_prerequisites() {
    log_step "1" "Checking backup prerequisites..."
    
    # Check if services are running (warn if not)
    local containers=("core-portainer" "core-surrealdb" "core-doppler")
    local running_count=0
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            ((running_count++))
            log_debug "✓ Container $container is running"
        else
            log_debug "✗ Container $container is not running"
        fi
    done
    
    if [[ $running_count -eq 0 ]]; then
        log_warn "No core services are currently running"
        log_warn "Backup will include stopped container data only"
    else
        log_debug "$running_count of 3 containers are running"
    fi
    
    # Check required tools
    local required_tools=("tar" "gzip" "sha256sum")
    if [[ "$ENCRYPT_BACKUP" == true ]]; then
        required_tools+=("gpg")
    fi
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
        log_debug "✓ Tool $tool is available"
    done
    
    # Check backup directory
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_debug "Creating backup directory: $BACKUP_DIR"
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$BACKUP_DIR"
            chmod 755 "$BACKUP_DIR"
        fi
    fi
    
    # Check write permissions
    if [[ "$DRY_RUN" == false ]]; then
        local test_file="${BACKUP_DIR}/.write_test"
        if ! touch "$test_file" 2>/dev/null; then
            log_error "Cannot write to backup directory: $BACKUP_DIR"
            exit 1
        fi
        rm -f "$test_file"
    fi
    
    # Check available space
    local available_space
    available_space=$(df "$BACKUP_DIR" | awk 'NR==2 {print int($4/1024)}')
    local estimated_size
    estimated_size=$(estimate_backup_size)
    
    if [[ $available_space -lt $estimated_size ]]; then
        log_warn "Available space ($available_space MB) may be insufficient for backup (estimated: $estimated_size MB)"
        if [[ "$AUTO_CONFIRM" == false ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    log_info "Prerequisites check completed successfully"
}

# Estimate backup size
estimate_backup_size() {
    local total_size=0
    
    # Estimate Portainer data size
    if [[ -d "/volume1/docker/core/portainer/data" ]]; then
        local portainer_size
        portainer_size=$(du -sm "/volume1/docker/core/portainer/data" 2>/dev/null | cut -f1 || echo "0")
        total_size=$((total_size + portainer_size))
    fi
    
    # Estimate SurrealDB data size
    if [[ -d "/volume1/docker/core/surrealdb/data" ]]; then
        local surrealdb_size
        surrealdb_size=$(du -sm "/volume1/docker/core/surrealdb/data" 2>/dev/null | cut -f1 || echo "0")
        total_size=$((total_size + surrealdb_size))
    fi
    
    # Add overhead for compression and metadata
    total_size=$((total_size + 50))
    
    echo $total_size
}

# Generate backup metadata
generate_metadata() {
    local backup_timestamp="$1"
    local backup_path="$2"
    
    cat > "${backup_path}/backup-metadata.json" << EOF
{
  "backup_info": {
    "timestamp": "$backup_timestamp",
    "type": "$BACKUP_TYPE",
    "version": "1.0.0",
    "created_by": "$(whoami)@$(hostname)",
    "script_version": "1.0.0"
  },
  "system_info": {
    "hostname": "$(hostname)",
    "os_info": "$(uname -a)",
    "docker_version": "$(docker --version 2>/dev/null || echo 'N/A')",
    "compose_version": "$(docker-compose --version 2>/dev/null || echo 'N/A')"
  },
  "services_status": {
    "portainer_running": $(docker ps --format "{{.Names}}" | grep -q "^core-portainer$" && echo "true" || echo "false"),
    "surrealdb_running": $(docker ps --format "{{.Names}}" | grep -q "^core-surrealdb$" && echo "true" || echo "false"),
    "doppler_running": $(docker ps --format "{{.Names}}" | grep -q "^core-doppler$" && echo "true" || echo "false")
  },
  "backup_settings": {
    "compression": $COMPRESS_BACKUP,
    "encryption": $ENCRYPT_BACKUP,
    "verification": $VERIFY_BACKUP,
    "exclude_logs": $EXCLUDE_LOGS
  }
}
EOF
}

# Backup Portainer data
backup_portainer() {
    local backup_path="$1"
    
    log_debug "Backing up Portainer data..."
    
    local portainer_data="/volume1/docker/core/portainer/data"
    if [[ ! -d "$portainer_data" ]] || [[ -z "$(ls -A "$portainer_data" 2>/dev/null)" ]]; then
        log_warn "Portainer data directory is empty or doesn't exist"
        return 0
    fi
    
    local backup_file="${backup_path}/portainer-data"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Stop Portainer temporarily for consistent backup
        local was_running=false
        if docker ps --format "{{.Names}}" | grep -q "^core-portainer$"; then
            log_debug "Stopping Portainer for consistent backup..."
            docker stop core-portainer &>/dev/null || true
            was_running=true
            sleep 5
        fi
        
        # Create backup
        if [[ "$COMPRESS_BACKUP" == true ]]; then
            tar -czf "${backup_file}.tar.gz" -C "$portainer_data" . 2>/dev/null
            log_debug "Created compressed Portainer backup: ${backup_file}.tar.gz"
        else
            tar -cf "${backup_file}.tar" -C "$portainer_data" . 2>/dev/null
            log_debug "Created Portainer backup: ${backup_file}.tar"
        fi
        
        # Restart Portainer if it was running
        if [[ "$was_running" == true ]]; then
            log_debug "Restarting Portainer..."
            docker start core-portainer &>/dev/null || true
        fi
    fi
    
    log_info "✓ Portainer backup completed"
}

# Backup SurrealDB data
backup_surrealdb() {
    local backup_path="$1"
    
    log_debug "Backing up SurrealDB data..."
    
    local surrealdb_data="/volume1/docker/core/surrealdb/data"
    if [[ ! -d "$surrealdb_data" ]] || [[ -z "$(ls -A "$surrealdb_data" 2>/dev/null)" ]]; then
        log_warn "SurrealDB data directory is empty or doesn't exist"
        return 0
    fi
    
    local backup_file="${backup_path}/surrealdb-data"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Create hot backup if SurrealDB is running
        if docker ps --format "{{.Names}}" | grep -q "^core-surrealdb$"; then
            log_debug "Creating hot backup of running SurrealDB..."
            
            # Try to create a database export first
            local export_file="${backup_path}/surrealdb-export.sql"
            if docker exec core-surrealdb surreal export --endpoint http://localhost:8000 --user admin --pass "${SURREALDB_PASS:-}" --namespace core --database services "$export_file" &>/dev/null; then
                log_debug "Created SurrealDB export: $export_file"
            else
                log_debug "SurrealDB export failed, will backup raw data files"
            fi
        fi
        
        # Backup raw data files
        if [[ "$COMPRESS_BACKUP" == true ]]; then
            tar -czf "${backup_file}.tar.gz" -C "$surrealdb_data" . 2>/dev/null
            log_debug "Created compressed SurrealDB backup: ${backup_file}.tar.gz"
        else
            tar -cf "${backup_file}.tar" -C "$surrealdb_data" . 2>/dev/null
            log_debug "Created SurrealDB backup: ${backup_file}.tar"
        fi
    fi
    
    log_info "✓ SurrealDB backup completed"
}

# Backup configuration files
backup_configuration() {
    local backup_path="$1"
    
    log_debug "Backing up configuration files..."
    
    local config_backup="${backup_path}/configuration"
    
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$config_backup"
        
        # Backup .env file (with sensitive data protection)
        if [[ -f "${SCRIPT_DIR}/.env" ]]; then
            # Create sanitized version for backup
            grep -v "DOPPLER_TOKEN\|PASSWORD\|SECRET\|KEY" "${SCRIPT_DIR}/.env" > "${config_backup}/env-sanitized" 2>/dev/null || true
            log_debug "Created sanitized environment backup"
            
            # Full backup (encrypted if encryption is enabled)
            if [[ "$ENCRYPT_BACKUP" == true ]]; then
                cp "${SCRIPT_DIR}/.env" "${config_backup}/env-full"
                log_debug "Created full environment backup (will be encrypted)"
            fi
        fi
        
        # Backup docker-compose.yml
        if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
            cp "${SCRIPT_DIR}/docker-compose.yml" "${config_backup}/"
            log_debug "Backed up docker-compose.yml"
        fi
        
        # Backup Doppler configuration if available
        if [[ -d "${SCRIPT_DIR}/doppler" ]]; then
            cp -r "${SCRIPT_DIR}/doppler" "${config_backup}/"
            log_debug "Backed up Doppler configuration"
        fi
        
        # Backup scripts
        local scripts=("deploy.sh" "stop.sh" "backup.sh" "logs.sh" "status.sh" "update.sh")
        for script in "${scripts[@]}"; do
            if [[ -f "${SCRIPT_DIR}/$script" ]]; then
                cp "${SCRIPT_DIR}/$script" "${config_backup}/"
                log_debug "Backed up script: $script"
            fi
        done
    fi
    
    log_info "✓ Configuration backup completed"
}

# Backup logs
backup_logs() {
    local backup_path="$1"
    
    if [[ "$EXCLUDE_LOGS" == true ]]; then
        log_debug "Skipping log backup (excluded by user)"
        return 0
    fi
    
    log_debug "Backing up service logs..."
    
    local logs_backup="${backup_path}/logs"
    
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$logs_backup"
        
        # Backup container logs
        local containers=("core-portainer" "core-surrealdb" "core-doppler")
        for container in "${containers[@]}"; do
            if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
                docker logs "$container" &> "${logs_backup}/${container}.log" 2>/dev/null || true
                log_debug "Backed up logs for: $container"
            fi
        done
        
        # Backup script logs
        local script_logs=("deployment.log" "backup.log" "stop.log")
        for log_file in "${script_logs[@]}"; do
            if [[ -f "${SCRIPT_DIR}/$log_file" ]]; then
                cp "${SCRIPT_DIR}/$log_file" "$logs_backup/"
                log_debug "Backed up: $log_file"
            fi
        done
    fi
    
    log_info "✓ Logs backup completed"
}

# Encrypt backup
encrypt_backup() {
    local backup_path="$1"
    
    if [[ "$ENCRYPT_BACKUP" == false ]]; then
        return 0
    fi
    
    log_step "5" "Encrypting backup files..."
    
    # Check if GPG is available
    if ! command -v gpg &> /dev/null; then
        log_error "GPG is not installed. Cannot encrypt backup."
        exit 1
    fi
    
    # Get encryption passphrase
    local passphrase=""
    if [[ "$AUTO_CONFIRM" == false ]]; then
        echo
        read -s -p "Enter encryption passphrase: " passphrase
        echo
        read -s -p "Confirm encryption passphrase: " passphrase_confirm
        echo
        
        if [[ "$passphrase" != "$passphrase_confirm" ]]; then
            log_error "Passphrases do not match"
            exit 1
        fi
    else
        # In automated mode, use environment variable or generate one
        passphrase="${BACKUP_ENCRYPTION_PASSPHRASE:-$(openssl rand -base64 32)}"
        log_warn "Using automated encryption passphrase. Store securely!"
        echo "Backup encryption passphrase: $passphrase" > "${backup_path}/ENCRYPTION_KEY.txt"
        chmod 600 "${backup_path}/ENCRYPTION_KEY.txt"
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        # Encrypt all backup files
        find "$backup_path" -type f \( -name "*.tar.gz" -o -name "*.tar" -o -name "env-full" \) | while read -r file; do
            log_debug "Encrypting: $(basename "$file")"
            echo "$passphrase" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "${file}.gpg" "$file"
            rm "$file"  # Remove unencrypted version
        done
    fi
    
    log_info "✓ Backup encryption completed"
}

# Generate checksums
generate_checksums() {
    local backup_path="$1"
    
    log_debug "Generating backup checksums..."
    
    if [[ "$DRY_RUN" == false ]]; then
        local checksum_file="${backup_path}/checksums.sha256"
        find "$backup_path" -type f ! -name "checksums.sha256" -exec sha256sum {} \; > "$checksum_file"
        log_debug "Generated checksums file: $checksum_file"
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_path="$1"
    
    if [[ "$VERIFY_BACKUP" == false ]]; then
        log_debug "Skipping backup verification (disabled by user)"
        return 0
    fi
    
    log_step "6" "Verifying backup integrity..."
    
    if [[ "$DRY_RUN" == false ]]; then
        local checksum_file="${backup_path}/checksums.sha256"
        if [[ -f "$checksum_file" ]]; then
            if (cd "$backup_path" && sha256sum -c "$checksum_file" &>/dev/null); then
                log_info "✓ Backup integrity verification passed"
            else
                log_error "Backup integrity verification failed!"
                exit 1
            fi
        else
            log_warn "No checksums file found, skipping verification"
        fi
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    if [[ "$CLEANUP_OLD" == false ]]; then
        log_debug "Skipping cleanup of old backups (disabled by user)"
        return 0
    fi
    
    log_step "7" "Cleaning up old backups..."
    
    if [[ "$DRY_RUN" == false ]]; then
        local deleted_count=0
        
        # Find and remove backups older than retention period
        find "$BACKUP_DIR" -maxdepth 1 -type d -name "*_*" -mtime "+$RETENTION_DAYS" | while read -r old_backup; do
            log_debug "Removing old backup: $(basename "$old_backup")"
            rm -rf "$old_backup"
            ((deleted_count++))
        done
        
        if [[ $deleted_count -gt 0 ]]; then
            log_info "✓ Cleaned up $deleted_count old backups (older than $RETENTION_DAYS days)"
        else
            log_debug "No old backups to clean up"
        fi
    fi
}

# Create backup
create_backup() {
    log_step "3" "Creating backup..."
    
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/${backup_timestamp}"
    
    log_info "Creating backup at: $backup_path"
    
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$backup_path"
        chmod 755 "$backup_path"
        
        # Generate metadata first
        generate_metadata "$backup_timestamp" "$backup_path"
    fi
    
    # Perform backup based on type
    case "$BACKUP_TYPE" in
        "full")
            backup_portainer "$backup_path"
            backup_surrealdb "$backup_path"
            backup_configuration "$backup_path"
            backup_logs "$backup_path"
            ;;
        "data")
            backup_portainer "$backup_path"
            backup_surrealdb "$backup_path"
            ;;
        "config")
            backup_configuration "$backup_path"
            ;;
        *)
            log_error "Unknown backup type: $BACKUP_TYPE"
            exit 1
            ;;
    esac
    
    if [[ "$DRY_RUN" == false ]]; then
        # Generate checksums
        generate_checksums "$backup_path"
        
        # Encrypt if requested
        encrypt_backup "$backup_path"
        
        # Set final permissions
        chmod -R 600 "$backup_path"/*
        chmod 700 "$backup_path"
    fi
    
    log_info "✓ Backup creation completed: $backup_path"
    echo "$backup_path"  # Return backup path for other functions
}

# Show backup summary
show_backup_summary() {
    local backup_path="$1"
    
    log_step "8" "Backup Summary"
    
    local backup_size="0"
    if [[ -d "$backup_path" ]] && [[ "$DRY_RUN" == false ]]; then
        backup_size=$(du -sh "$backup_path" | cut -f1)
    fi
    
    cat << EOF

${GREEN}✅ Core Services Backup Complete!${NC}

${YELLOW}📊 Backup Information:${NC}
• Type: $BACKUP_TYPE
• Location: $backup_path
• Size: $backup_size
• Compression: $(if [[ "$COMPRESS_BACKUP" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
• Encryption: $(if [[ "$ENCRYPT_BACKUP" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
• Verification: $(if [[ "$VERIFY_BACKUP" == true ]]; then echo "Passed"; else echo "Skipped"; fi)

${YELLOW}📁 Backup Contents:${NC}
$(if [[ "$BACKUP_TYPE" == "full" || "$BACKUP_TYPE" == "data" ]]; then echo "• Portainer data and configurations"; fi)
$(if [[ "$BACKUP_TYPE" == "full" || "$BACKUP_TYPE" == "data" ]]; then echo "• SurrealDB database files"; fi)
$(if [[ "$BACKUP_TYPE" == "full" || "$BACKUP_TYPE" == "config" ]]; then echo "• Environment configuration"; fi)
$(if [[ "$BACKUP_TYPE" == "full" || "$BACKUP_TYPE" == "config" ]]; then echo "• Docker Compose files"; fi)
$(if [[ "$BACKUP_TYPE" == "full" && "$EXCLUDE_LOGS" == false ]]; then echo "• Service logs"; fi)
• Backup metadata and checksums

${YELLOW}🔧 Restoration:${NC}
• Manual restore: See MIGRATION.md
• Verify backup: sha256sum -c checksums.sha256
• Decrypt files: gpg --decrypt file.gpg > file

${YELLOW}📝 Retention:${NC}
• Current retention: $RETENTION_DAYS days
• Next cleanup: $(date -d "+1 day" '+%Y-%m-%d')

$(if [[ "$ENCRYPT_BACKUP" == true ]]; then
    echo "${RED}🔐 Security Notice:${NC}"
    echo "• Backup is encrypted - store passphrase securely!"
    echo "• Without passphrase, backup cannot be restored"
fi)

For automation, add to crontab or DSM Task Scheduler.
For more information, see README.md

EOF

    log_info "Backup completed successfully at $(date)"
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
            -e|--encrypt)
                ENCRYPT_BACKUP=true
                shift
                ;;
            -c|--no-compress)
                COMPRESS_BACKUP=false
                shift
                ;;
            -n|--no-verify)
                VERIFY_BACKUP=false
                shift
                ;;
            -k|--no-cleanup)
                CLEANUP_OLD=false
                shift
                ;;
            -r|--retention)
                if [[ -n "$2" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    RETENTION_DAYS="$2"
                    shift 2
                else
                    log_error "Invalid retention days: $2"
                    exit 1
                fi
                ;;
            -o|--output)
                if [[ -n "$2" ]]; then
                    BACKUP_DIR="$2"
                    shift 2
                else
                    log_error "Output directory not specified"
                    exit 1
                fi
                ;;
            -t|--type)
                if [[ -n "$2" ]] && [[ "$2" =~ ^(full|data|config)$ ]]; then
                    BACKUP_TYPE="$2"
                    shift 2
                else
                    log_error "Invalid backup type: $2 (must be: full, data, or config)"
                    exit 1
                fi
                ;;
            -x|--exclude-logs)
                EXCLUDE_LOGS=true
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

# Main backup function
main() {
    # Initialize log file
    echo "=== Core Services Backup Started at $(date) ===" > "$LOG_FILE"
    
    log_info "Starting unified core services backup..."
    log_debug "Script directory: $SCRIPT_DIR"
    log_debug "Options: VERBOSE=$VERBOSE, DRY_RUN=$DRY_RUN, AUTO_CONFIRM=$AUTO_CONFIRM, ENCRYPT_BACKUP=$ENCRYPT_BACKUP"
    log_debug "Backup settings: TYPE=$BACKUP_TYPE, DIR=$BACKUP_DIR, RETENTION=$RETENTION_DAYS days"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "Running in DRY RUN mode - no backup will be created"
    fi
    
    # Execute backup steps
    check_prerequisites
    
    local backup_path
    backup_path=$(create_backup)
    
    if [[ "$DRY_RUN" == false ]]; then
        verify_backup "$backup_path"
        cleanup_old_backups
    fi
    
    show_backup_summary "$backup_path"
    
    log_info "Backup script completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi