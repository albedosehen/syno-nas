#!/bin/bash
set -euo pipefail

# ===========================================
# UNIFIED CORE SERVICES DEPLOYMENT SCRIPT
# ===========================================
# Automated deployment script for Synology NAS DS1520+
# Services: Portainer, SurrealDB, Doppler
# Platform: Linux/Synology DSM 7.2+
#
# Usage: ./deploy.sh [OPTIONS]
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
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly BACKUP_DIR="/volume1/docker/backups/core"
readonly ROLLBACK_STATE_FILE="${SCRIPT_DIR}/.rollback_state"

# Global variables
VERBOSE=false
DRY_RUN=false
FORCE_DEPLOY=false
SKIP_BACKUP=false
AUTO_CONFIRM=false

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
    
    if [[ -f "$ROLLBACK_STATE_FILE" ]]; then
        log_warn "Attempting automatic rollback..."
        perform_rollback
    fi
    
    cleanup_on_exit
    exit $exit_code
}

trap 'handle_error ${LINENO}' ERR

# Cleanup function
cleanup_on_exit() {
    log_debug "Performing cleanup operations..."
    # Remove temporary files if any
    [[ -f "/tmp/core-services-backup.tar.gz" ]] && rm -f "/tmp/core-services-backup.tar.gz"
}

trap cleanup_on_exit EXIT

# Help function
show_help() {
    cat << EOF
${CYAN}Unified Core Services Deployment Script${NC}

${YELLOW}USAGE:${NC}
    $0 [OPTIONS]

${YELLOW}DESCRIPTION:${NC}
    Automated deployment script for unified core services stack including
    Portainer (container management), SurrealDB (database), and Doppler (secrets).
    
    Optimized for Synology NAS DS1520+ with DSM 7.2+

${YELLOW}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be done without executing
    -f, --force             Force deployment even if services are running
    -s, --skip-backup       Skip backup creation before deployment
    -y, --yes               Auto-confirm all prompts
    
${YELLOW}EXAMPLES:${NC}
    $0                      # Standard deployment with prompts
    $0 -v                   # Verbose deployment
    $0 -d                   # Dry run to see what would happen
    $0 -f -y               # Force deployment with auto-confirm
    $0 --skip-backup -y     # Quick deployment without backup

${YELLOW}PREREQUISITES:${NC}
    • Synology DSM 7.2+ with Docker package installed
    • SSH access with admin privileges
    • Minimum 2GB available RAM
    • 1GB free storage space
    • Valid Doppler account and service token

${YELLOW}FILES CREATED/MODIFIED:${NC}
    • /volume1/docker/core/          (Service data directories)
    • /volume1/docker/backups/core/  (Backup storage)
    • ./deployment.log               (Deployment log)
    • ./.env                         (Environment configuration)

For more information, see README.md or visit:
https://github.com/your-repo/syno-nas/docker/compositions/core
EOF
}

# Prerequisite checking functions
check_system_requirements() {
    log_step "1" "Checking system requirements..."
    
    # Check if running on Synology
    if [[ ! -f "/etc/synoinfo.conf" ]]; then
        log_warn "Not running on Synology DSM - some features may not work optimally"
    else
        log_debug "Detected Synology DSM system"
        local dsm_version
        dsm_version=$(grep -oP 'productversion="\K[^"]*' /etc/synoinfo.conf 2>/dev/null || echo "unknown")
        log_debug "DSM Version: $dsm_version"
    fi
    
    # Check Docker installation
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker via DSM Package Center."
        exit 1
    fi
    
    local docker_version
    docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+')
    log_debug "Docker version: $docker_version"
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed."
        exit 1
    fi
    
    local compose_version
    compose_version=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+')
    log_debug "Docker Compose version: $compose_version"
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker service."
        exit 1
    fi
    
    # Check available memory
    local available_memory
    available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [[ $available_memory -lt 2048 ]]; then
        log_warn "Available memory ($available_memory MB) is less than recommended 2GB"
        if [[ "$FORCE_DEPLOY" == false ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    # Check available disk space
    local available_space
    available_space=$(df /volume1 2>/dev/null | awk 'NR==2 {print int($4/1024)}' || echo "0")
    if [[ $available_space -lt 1024 ]]; then
        log_warn "Available disk space ($available_space MB) is less than recommended 1GB"
        if [[ "$FORCE_DEPLOY" == false ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    log_info "System requirements check completed successfully"
}

check_permissions() {
    log_step "2" "Checking file permissions and user access..."
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        log_debug "Running as root user"
    else
        log_debug "Running as user: $(whoami)"
        
        # Check if user is in docker group
        if ! groups | grep -q docker; then
            log_error "Current user is not in the docker group. Please run: sudo usermod -a -G docker \$(whoami)"
            exit 1
        fi
    fi
    
    # Check write permissions for Docker directories
    local docker_base_dir="/volume1/docker"
    if [[ ! -d "$docker_base_dir" ]]; then
        log_debug "Creating Docker base directory: $docker_base_dir"
        if [[ "$DRY_RUN" == false ]]; then
            sudo mkdir -p "$docker_base_dir"
            sudo chown -R 1000:1000 "$docker_base_dir"
        fi
    fi
    
    # Test write permissions
    local test_file="${docker_base_dir}/.permission_test"
    if [[ "$DRY_RUN" == false ]]; then
        if ! touch "$test_file" 2>/dev/null; then
            log_error "Cannot write to $docker_base_dir. Please check permissions."
            exit 1
        fi
        rm -f "$test_file"
    fi
    
    log_info "Permissions check completed successfully"
}

validate_configuration() {
    log_step "3" "Validating configuration files..."
    
    # Check if .env file exists
    if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
        log_warn ".env file not found. Creating from template..."
        if [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
            if [[ "$DRY_RUN" == false ]]; then
                cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
                log_info "Created .env file from template. Please review and update configuration."
                if [[ "$AUTO_CONFIRM" == false ]]; then
                    read -p "Press Enter to continue after reviewing .env file..." -r
                fi
            fi
        else
            log_error ".env.example template not found. Cannot create configuration."
            exit 1
        fi
    fi
    
    # Source environment variables
    set -a  # automatically export all variables
    source "${SCRIPT_DIR}/.env"
    set +a
    
    # Validate critical environment variables
    local required_vars=(
        "DOPPLER_TOKEN"
        "DOPPLER_PROJECT"
        "PORTAINER_PORT"
        "SURREALDB_PORT"
        "PUID"
        "PGID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable '$var' is not set in .env file"
            exit 1
        fi
        log_debug "✓ $var is set"
    done
    
    # Validate Doppler token format
    if [[ ! "$DOPPLER_TOKEN" =~ ^dp\.pt\. ]]; then
        log_error "DOPPLER_TOKEN format appears invalid (should start with 'dp.pt.')"
        exit 1
    fi
    
    # Check port conflicts
    local ports=("$PORTAINER_PORT" "$SURREALDB_PORT" "${PORTAINER_EDGE_PORT:-8000}")
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warn "Port $port is already in use"
            if [[ "$FORCE_DEPLOY" == false ]]; then
                read -p "Continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
        fi
    done
    
    log_info "Configuration validation completed successfully"
}

create_directory_structure() {
    log_step "4" "Creating directory structure..."
    
    local directories=(
        "/volume1/docker/core"
        "/volume1/docker/core/portainer/data"
        "/volume1/docker/core/surrealdb/data"
        "/volume1/docker/core/surrealdb/config"
        "/volume1/docker/core/doppler"
        "/volume1/docker/backups/core"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_debug "Creating directory: $dir"
            if [[ "$DRY_RUN" == false ]]; then
                sudo mkdir -p "$dir"
                sudo chown -R "${PUID:-1000}:${PGID:-1000}" "$dir"
                sudo chmod -R 755 "$dir"
            fi
        else
            log_debug "Directory already exists: $dir"
        fi
    done
    
    log_info "Directory structure created successfully"
}

save_rollback_state() {
    log_debug "Saving rollback state..."
    
    if [[ "$DRY_RUN" == false ]]; then
        cat > "$ROLLBACK_STATE_FILE" << EOF
# Rollback state saved at $(date)
CONTAINERS_BEFORE_DEPLOY="$(docker ps --format "{{.Names}}" | grep -E "(portainer|surrealdb|doppler)" | tr '\n' ' ' || echo "")"
NETWORKS_BEFORE_DEPLOY="$(docker network ls --format "{{.Name}}" | grep core || echo "")"
DEPLOYMENT_TIMESTAMP="$(date +%s)"
BACKUP_CREATED="$([[ "$SKIP_BACKUP" == false ]] && echo "true" || echo "false")"
EOF
    fi
}

perform_rollback() {
    log_warn "Performing rollback to previous state..."
    
    if [[ ! -f "$ROLLBACK_STATE_FILE" ]]; then
        log_error "No rollback state found. Manual cleanup may be required."
        return 1
    fi
    
    source "$ROLLBACK_STATE_FILE"
    
    # Stop and remove new containers
    log_debug "Stopping and removing containers..."
    docker-compose down --remove-orphans 2>/dev/null || true
    
    # Remove networks created during deployment
    log_debug "Cleaning up networks..."
    docker network rm core-network 2>/dev/null || true
    
    log_info "Rollback completed. Please check system state manually."
    rm -f "$ROLLBACK_STATE_FILE"
}

create_backup() {
    if [[ "$SKIP_BACKUP" == true ]]; then
        log_debug "Skipping backup creation as requested"
        return 0
    fi
    
    log_step "5" "Creating backup of existing data..."
    
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${BACKUP_DIR}/${backup_timestamp}"
    
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$backup_dir"
        
        # Backup existing data if present
        if [[ -d "/volume1/docker/core/portainer/data" ]] && [[ "$(ls -A /volume1/docker/core/portainer/data 2>/dev/null)" ]]; then
            log_debug "Backing up Portainer data..."
            tar -czf "${backup_dir}/portainer-backup.tar.gz" -C "/volume1/docker/core/portainer/data" . 2>/dev/null || true
        fi
        
        if [[ -d "/volume1/docker/core/surrealdb/data" ]] && [[ "$(ls -A /volume1/docker/core/surrealdb/data 2>/dev/null)" ]]; then
            log_debug "Backing up SurrealDB data..."
            tar -czf "${backup_dir}/surrealdb-backup.tar.gz" -C "/volume1/docker/core/surrealdb/data" . 2>/dev/null || true
        fi
        
        # Backup current configuration
        if [[ -f "${SCRIPT_DIR}/.env" ]]; then
            cp "${SCRIPT_DIR}/.env" "${backup_dir}/env-backup"
        fi
        
        # Backup docker-compose.yml
        if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
            cp "${SCRIPT_DIR}/docker-compose.yml" "${backup_dir}/docker-compose-backup.yml"
        fi
        
        log_info "Backup created at: $backup_dir"
    fi
}

test_doppler_connectivity() {
    log_step "6" "Testing Doppler connectivity..."
    
    # Test Doppler authentication locally if doppler CLI is available
    if command -v doppler &> /dev/null; then
        log_debug "Testing Doppler authentication with CLI..."
        if DOPPLER_TOKEN="$DOPPLER_TOKEN" doppler me &> /dev/null; then
            log_debug "✓ Doppler authentication successful"
        else
            log_error "Doppler authentication failed. Please check your DOPPLER_TOKEN."
            exit 1
        fi
    else
        log_debug "Doppler CLI not available, will test connectivity via container"
    fi
    
    log_info "Doppler connectivity test completed"
}

build_and_deploy() {
    log_step "7" "Building and deploying services..."
    
    # Save current state for potential rollback
    save_rollback_state
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would execute: docker-compose up -d --build"
        return 0
    fi
    
    # Pull latest images
    log_debug "Pulling latest images..."
    docker-compose pull 2>&1 | tee -a "$LOG_FILE"
    
    # Build custom images (Doppler)
    log_debug "Building custom images..."
    docker-compose build 2>&1 | tee -a "$LOG_FILE"
    
    # Deploy services
    log_debug "Starting services..."
    docker-compose up -d 2>&1 | tee -a "$LOG_FILE"
    
    log_info "Services deployment initiated"
}

verify_deployment() {
    log_step "8" "Verifying deployment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would verify service health and connectivity"
        return 0
    fi
    
    # Wait for services to start
    log_debug "Waiting for services to initialize..."
    sleep 30
    
    # Check container status
    local containers=("core-doppler" "core-surrealdb" "core-portainer")
    local all_healthy=true
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            log_debug "✓ Container $container is running"
            
            # Check health status if available
            local health_status
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
            if [[ "$health_status" == "healthy" ]]; then
                log_debug "✓ Container $container is healthy"
            elif [[ "$health_status" == "starting" ]]; then
                log_debug "⚠ Container $container is still starting..."
                sleep 10
            elif [[ "$health_status" != "no-healthcheck" ]]; then
                log_warn "Container $container health status: $health_status"
                all_healthy=false
            fi
        else
            log_error "Container $container is not running"
            all_healthy=false
        fi
    done
    
    # Test service connectivity
    log_debug "Testing service connectivity..."
    
    # Test Portainer
    local portainer_url="http://localhost:${PORTAINER_PORT}"
    if curl -f -s "$portainer_url" &>/dev/null; then
        log_debug "✓ Portainer is accessible at $portainer_url"
    else
        log_warn "Portainer may not be fully ready at $portainer_url"
        all_healthy=false
    fi
    
    # Test SurrealDB
    local surrealdb_url="http://localhost:${SURREALDB_PORT}/health"
    if curl -f -s "$surrealdb_url" &>/dev/null; then
        log_debug "✓ SurrealDB is accessible at http://localhost:${SURREALDB_PORT}"
    else
        log_warn "SurrealDB may not be fully ready at http://localhost:${SURREALDB_PORT}"
        all_healthy=false
    fi
    
    # Test inter-service communication
    log_debug "Testing inter-service communication..."
    if docker-compose exec -T portainer ping -c 1 core-surrealdb &>/dev/null; then
        log_debug "✓ Portainer can communicate with SurrealDB"
    else
        log_warn "Inter-service communication test failed"
        all_healthy=false
    fi
    
    if [[ "$all_healthy" == true ]]; then
        log_info "Deployment verification completed successfully"
        # Remove rollback state on successful deployment
        rm -f "$ROLLBACK_STATE_FILE"
    else
        log_warn "Some verification checks failed. Services may need time to fully initialize."
        log_info "Run './status.sh' to check service health, or './logs.sh' to view logs."
    fi
}

show_deployment_summary() {
    log_step "9" "Deployment Summary"
    
    cat << EOF

${GREEN}🎉 Core Services Deployment Complete!${NC}

${YELLOW}📊 Service Access URLs:${NC}
• Portainer:  http://$(hostname -I | awk '{print $1}'):${PORTAINER_PORT}
• SurrealDB:  http://$(hostname -I | awk '{print $1}'):${SURREALDB_PORT}
• Doppler:    Internal service (no direct access)

${YELLOW}🔧 Management Commands:${NC}
• Check Status:    ./status.sh
• View Logs:       ./logs.sh
• Create Backup:   ./backup.sh
• Stop Services:   ./stop.sh
• Update Services: ./update.sh

${YELLOW}📁 Important Paths:${NC}
• Data Directory:   /volume1/docker/core/
• Backup Directory: /volume1/docker/backups/core/
• Logs:            ${LOG_FILE}

${YELLOW}🔐 Security Notes:${NC}
• Portainer: Create admin account on first visit
• SurrealDB: Authentication via Doppler-managed credentials
• Network:   Services isolated on core-network (172.20.0.0/16)

${YELLOW}📖 Next Steps:${NC}
1. Visit Portainer UI to set up admin account
2. Configure additional secrets in Doppler dashboard
3. Review and customize .env file for production use
4. Set up automated backups using ./backup.sh in cron/Task Scheduler

For troubleshooting and advanced configuration, see README.md

EOF

    log_info "Deployment completed successfully at $(date)"
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
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -s|--skip-backup)
                SKIP_BACKUP=true
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

# Main deployment function
main() {
    # Initialize log file
    echo "=== Core Services Deployment Started at $(date) ===" > "$LOG_FILE"
    
    log_info "Starting unified core services deployment..."
    log_debug "Script directory: $SCRIPT_DIR"
    log_debug "Options: VERBOSE=$VERBOSE, DRY_RUN=$DRY_RUN, FORCE_DEPLOY=$FORCE_DEPLOY, SKIP_BACKUP=$SKIP_BACKUP, AUTO_CONFIRM=$AUTO_CONFIRM"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "Running in DRY RUN mode - no changes will be made"
    fi
    
    # Execute deployment steps
    check_system_requirements
    check_permissions
    validate_configuration
    create_directory_structure
    create_backup
    test_doppler_connectivity
    build_and_deploy
    verify_deployment
    show_deployment_summary
    
    log_info "Deployment script completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi