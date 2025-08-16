#!/bin/bash

# ==============================================================================
# Synology NAS Docker Management - Environment Setup Script
# ==============================================================================
# 
# This script automates environment configuration for the Synology NAS Docker
# management project. It handles different deployment scenarios, validates
# environment variables, and ensures proper configuration for services.
#
# Compatible with Synology DSM 7.2+ and standard Linux environments.
#
# Author: Synology NAS Docker Management Project
# Version: 1.0.0
# ==============================================================================

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="${LOG_DIR}/setup-environment_${TIMESTAMP}.log"

# Environment files
readonly GLOBAL_ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"
readonly GLOBAL_ENV_FILE="${PROJECT_ROOT}/.env"
readonly COMPOSITIONS_DIR="${PROJECT_ROOT}/docker/compositions"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration
DEPLOYMENT_TYPE=""
INTERACTIVE_MODE=true
FORCE_OVERWRITE=false
BACKUP_EXISTING=true
VALIDATE_CONFIG=true
SETUP_SERVICES=true
DRY_RUN=false

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Log to console with colors
    case "$level" in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
        *)
            echo "[$level] $message"
            ;;
    esac
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

print_header() {
    echo -e "${CYAN}"
    echo "===================================================================="
    echo "  Synology NAS Docker Management - Environment Setup"
    echo "===================================================================="
    echo -e "${NC}"
}

print_section() {
    echo -e "\n${BLUE}>>> $1${NC}"
}

print_subsection() {
    echo -e "${PURPLE}  → $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local description="$3"
    local percentage=$((current * 100 / total))
    local completed=$((current * 50 / total))
    local remaining=$((50 - completed))
    
    printf "\r${CYAN}[%-50s] %d%% %s${NC}" \
        "$(printf "%${completed}s" | tr ' ' '=')" \
        "$percentage" \
        "$description"
    
    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

# ==============================================================================
# Environment Setup Functions
# ==============================================================================

check_prerequisites() {
    print_section "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "git" "curl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_tools+=("$cmd")
        else
            print_success "$cmd is available"
        fi
    done
    
    # Check for Synology-specific tools
    if [[ -f "/usr/syno/bin/synopkg" ]]; then
        print_success "Synology DSM environment detected"
        export SYNOLOGY_ENV=true
    else
        log "INFO" "Standard Linux environment detected"
        export SYNOLOGY_ENV=false
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        missing_tools+=("docker-daemon")
        print_error "Docker daemon is not running"
    else
        print_success "Docker daemon is running"
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error_exit "Missing required tools: ${missing_tools[*]}"
    fi
    
    log "INFO" "All prerequisites satisfied"
}

detect_deployment_type() {
    if [ -n "$DEPLOYMENT_TYPE" ]; then
        return 0
    fi
    
    print_section "Detecting Deployment Type"
    
    # Check for existing environment indicators
    if [ -f "$GLOBAL_ENV_FILE" ]; then
        if grep -q "ENVIRONMENT=production" "$GLOBAL_ENV_FILE" 2>/dev/null; then
            DEPLOYMENT_TYPE="production"
        elif grep -q "ENVIRONMENT=staging" "$GLOBAL_ENV_FILE" 2>/dev/null; then
            DEPLOYMENT_TYPE="staging"
        elif grep -q "ENVIRONMENT=development" "$GLOBAL_ENV_FILE" 2>/dev/null; then
            DEPLOYMENT_TYPE="development"
        fi
    fi
    
    # Interactive selection if not detected
    if [ -z "$DEPLOYMENT_TYPE" ] && [ "$INTERACTIVE_MODE" = true ]; then
        echo "Please select your deployment type:"
        echo "1) Development - For local development and testing"
        echo "2) Staging - For testing in production-like environment"
        echo "3) Production - For live production deployment"
        echo
        
        while true; do
            read -p "Enter your choice (1-3): " choice
            case $choice in
                1)
                    DEPLOYMENT_TYPE="development"
                    break
                    ;;
                2)
                    DEPLOYMENT_TYPE="staging"
                    break
                    ;;
                3)
                    DEPLOYMENT_TYPE="production"
                    break
                    ;;
                *)
                    print_error "Invalid choice. Please enter 1, 2, or 3."
                    ;;
            esac
        done
    fi
    
    # Default to development if still not set
    if [ -z "$DEPLOYMENT_TYPE" ]; then
        DEPLOYMENT_TYPE="development"
        print_warning "No deployment type specified, defaulting to development"
    fi
    
    print_success "Deployment type: $DEPLOYMENT_TYPE"
    log "INFO" "Deployment type set to: $DEPLOYMENT_TYPE"
}

backup_existing_config() {
    if [ "$BACKUP_EXISTING" = false ]; then
        return 0
    fi
    
    print_section "Backing Up Existing Configuration"
    
    local backup_dir="${PROJECT_ROOT}/backups/env_${TIMESTAMP}"
    local backed_up=false
    
    if [ -f "$GLOBAL_ENV_FILE" ]; then
        mkdir -p "$backup_dir"
        cp "$GLOBAL_ENV_FILE" "$backup_dir/"
        print_success "Backed up existing .env to $backup_dir"
        backed_up=true
    fi
    
    # Backup service-specific .env files
    while IFS= read -r -d '' env_file; do
        if [ ! "$backed_up" = true ]; then
            mkdir -p "$backup_dir"
            backed_up=true
        fi
        
        local relative_path="${env_file#$PROJECT_ROOT/}"
        local backup_path="$backup_dir/$(dirname "$relative_path")"
        mkdir -p "$backup_path"
        cp "$env_file" "$backup_path/"
        print_success "Backed up $relative_path"
    done < <(find "$COMPOSITIONS_DIR" -name ".env" -type f -print0 2>/dev/null || true)
    
    if [ "$backed_up" = true ]; then
        log "INFO" "Configuration backup created in $backup_dir"
    else
        log "INFO" "No existing configuration found to backup"
    fi
}

create_global_environment() {
    print_section "Creating Global Environment Configuration"
    
    if [ ! -f "$GLOBAL_ENV_EXAMPLE" ]; then
        error_exit "Global .env.example file not found at $GLOBAL_ENV_EXAMPLE"
    fi
    
    if [ -f "$GLOBAL_ENV_FILE" ] && [ "$FORCE_OVERWRITE" = false ]; then
        if [ "$INTERACTIVE_MODE" = true ]; then
            echo "Global .env file already exists."
            read -p "Do you want to overwrite it? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_warning "Skipping global environment creation"
                return 0
            fi
        else
            print_warning "Global .env file exists, skipping (use --force to overwrite)"
            return 0
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN: Would create global .env file"
        return 0
    fi
    
    # Copy template and customize for deployment type
    cp "$GLOBAL_ENV_EXAMPLE" "$GLOBAL_ENV_FILE"
    
    # Update deployment-specific settings
    case "$DEPLOYMENT_TYPE" in
        "development")
            setup_development_environment
            ;;
        "staging")
            setup_staging_environment
            ;;
        "production")
            setup_production_environment
            ;;
    esac
    
    print_success "Global environment configuration created"
    log "INFO" "Global .env file created for $DEPLOYMENT_TYPE environment"
}

setup_development_environment() {
    print_subsection "Configuring development environment"
    
    # Update environment variables for development
    sed -i.bak \
        -e 's/^ENVIRONMENT=.*/ENVIRONMENT=development/' \
        -e 's/^LOG_LEVEL=.*/LOG_LEVEL=DEBUG/' \
        -e 's/^ENABLE_DEBUG=.*/ENABLE_DEBUG=true/' \
        -e 's/^ENABLE_MONITORING=.*/ENABLE_MONITORING=false/' \
        -e 's/^BACKUP_RETENTION_DAYS=.*/BACKUP_RETENTION_DAYS=7/' \
        -e 's/^HEALTH_CHECK_INTERVAL=.*/HEALTH_CHECK_INTERVAL=60/' \
        "$GLOBAL_ENV_FILE"
    
    # Set development-specific defaults
    echo "" >> "$GLOBAL_ENV_FILE"
    echo "# Development Environment Overrides" >> "$GLOBAL_ENV_FILE"
    echo "DEV_MODE=true" >> "$GLOBAL_ENV_FILE"
    echo "AUTO_RESTART=true" >> "$GLOBAL_ENV_FILE"
    echo "ENABLE_LIVE_RELOAD=true" >> "$GLOBAL_ENV_FILE"
    
    print_success "Development environment configured"
}

setup_staging_environment() {
    print_subsection "Configuring staging environment"
    
    # Update environment variables for staging
    sed -i.bak \
        -e 's/^ENVIRONMENT=.*/ENVIRONMENT=staging/' \
        -e 's/^LOG_LEVEL=.*/LOG_LEVEL=INFO/' \
        -e 's/^ENABLE_DEBUG=.*/ENABLE_DEBUG=false/' \
        -e 's/^ENABLE_MONITORING=.*/ENABLE_MONITORING=true/' \
        -e 's/^BACKUP_RETENTION_DAYS=.*/BACKUP_RETENTION_DAYS=30/' \
        -e 's/^HEALTH_CHECK_INTERVAL=.*/HEALTH_CHECK_INTERVAL=30/' \
        "$GLOBAL_ENV_FILE"
    
    # Set staging-specific defaults
    echo "" >> "$GLOBAL_ENV_FILE"
    echo "# Staging Environment Overrides" >> "$GLOBAL_ENV_FILE"
    echo "STAGING_MODE=true" >> "$GLOBAL_ENV_FILE"
    echo "ENABLE_PERFORMANCE_MONITORING=true" >> "$GLOBAL_ENV_FILE"
    
    print_success "Staging environment configured"
}

setup_production_environment() {
    print_subsection "Configuring production environment"
    
    # Update environment variables for production
    sed -i.bak \
        -e 's/^ENVIRONMENT=.*/ENVIRONMENT=production/' \
        -e 's/^LOG_LEVEL=.*/LOG_LEVEL=WARN/' \
        -e 's/^ENABLE_DEBUG=.*/ENABLE_DEBUG=false/' \
        -e 's/^ENABLE_MONITORING=.*/ENABLE_MONITORING=true/' \
        -e 's/^BACKUP_RETENTION_DAYS=.*/BACKUP_RETENTION_DAYS=90/' \
        -e 's/^HEALTH_CHECK_INTERVAL=.*/HEALTH_CHECK_INTERVAL=15/' \
        "$GLOBAL_ENV_FILE"
    
    # Set production-specific defaults
    echo "" >> "$GLOBAL_ENV_FILE"
    echo "# Production Environment Overrides" >> "$GLOBAL_ENV_FILE"
    echo "PRODUCTION_MODE=true" >> "$GLOBAL_ENV_FILE"
    echo "ENABLE_SECURITY_MONITORING=true" >> "$GLOBAL_ENV_FILE"
    echo "ENABLE_AUTOMATED_BACKUPS=true" >> "$GLOBAL_ENV_FILE"
    echo "ENABLE_ALERTS=true" >> "$GLOBAL_ENV_FILE"
    
    print_success "Production environment configured"
}

setup_service_environments() {
    if [ "$SETUP_SERVICES" = false ]; then
        return 0
    fi
    
    print_section "Setting Up Service Environments"
    
    local services=()
    local service_count=0
    
    # Find all docker-compose.yml files
    while IFS= read -r -d '' compose_file; do
        local service_dir="$(dirname "$compose_file")"
        local service_name="$(basename "$service_dir")"
        services+=("$service_dir:$service_name")
        ((service_count++))
    done < <(find "$COMPOSITIONS_DIR" -name "docker-compose.yml" -type f -print0 2>/dev/null || true)
    
    if [ $service_count -eq 0 ]; then
        print_warning "No services found to configure"
        return 0
    fi
    
    log "INFO" "Found $service_count services to configure"
    
    local current=0
    for service_info in "${services[@]}"; do
        local service_dir="${service_info%:*}"
        local service_name="${service_info#*:}"
        ((current++))
        
        show_progress $current $service_count "Configuring $service_name"
        
        setup_service_environment "$service_dir" "$service_name"
    done
    
    print_success "All service environments configured"
}

setup_service_environment() {
    local service_dir="$1"
    local service_name="$2"
    local service_env_example="$service_dir/.env.example"
    local service_env_file="$service_dir/.env"
    
    # Skip if no .env.example exists
    if [ ! -f "$service_env_example" ]; then
        log "DEBUG" "No .env.example found for $service_name, skipping"
        return 0
    fi
    
    # Check if .env already exists
    if [ -f "$service_env_file" ] && [ "$FORCE_OVERWRITE" = false ]; then
        log "DEBUG" "Service .env already exists for $service_name, skipping"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log "DEBUG" "DRY RUN: Would create .env for $service_name"
        return 0
    fi
    
    # Copy template and customize
    cp "$service_env_example" "$service_env_file"
    
    # Update service-specific variables based on deployment type
    case "$DEPLOYMENT_TYPE" in
        "development")
            configure_service_development "$service_env_file" "$service_name"
            ;;
        "staging")
            configure_service_staging "$service_env_file" "$service_name"
            ;;
        "production")
            configure_service_production "$service_env_file" "$service_name"
            ;;
    esac
    
    log "DEBUG" "Service environment configured for $service_name"
}

configure_service_development() {
    local env_file="$1"
    local service_name="$2"
    
    # Common development settings
    if grep -q "^DEBUG=" "$env_file"; then
        sed -i.bak 's/^DEBUG=.*/DEBUG=true/' "$env_file"
    fi
    
    if grep -q "^LOG_LEVEL=" "$env_file"; then
        sed -i.bak 's/^LOG_LEVEL=.*/LOG_LEVEL=DEBUG/' "$env_file"
    fi
    
    # Service-specific development settings
    case "$service_name" in
        "portainer")
            # Portainer development settings
            echo "# Development settings for Portainer" >> "$env_file"
            ;;
        *)
            # Generic development settings
            echo "# Development settings for $service_name" >> "$env_file"
            ;;
    esac
}

configure_service_staging() {
    local env_file="$1"
    local service_name="$2"
    
    # Common staging settings
    if grep -q "^DEBUG=" "$env_file"; then
        sed -i.bak 's/^DEBUG=.*/DEBUG=false/' "$env_file"
    fi
    
    if grep -q "^LOG_LEVEL=" "$env_file"; then
        sed -i.bak 's/^LOG_LEVEL=.*/LOG_LEVEL=INFO/' "$env_file"
    fi
    
    echo "# Staging settings for $service_name" >> "$env_file"
}

configure_service_production() {
    local env_file="$1"
    local service_name="$2"
    
    # Common production settings
    if grep -q "^DEBUG=" "$env_file"; then
        sed -i.bak 's/^DEBUG=.*/DEBUG=false/' "$env_file"
    fi
    
    if grep -q "^LOG_LEVEL=" "$env_file"; then
        sed -i.bak 's/^LOG_LEVEL=.*/LOG_LEVEL=WARN/' "$env_file"
    fi
    
    echo "# Production settings for $service_name" >> "$env_file"
}

validate_environment() {
    if [ "$VALIDATE_CONFIG" = false ]; then
        return 0
    fi
    
    print_section "Validating Environment Configuration"
    
    local validation_script="$SCRIPT_DIR/validate-config.sh"
    
    if [ -f "$validation_script" ]; then
        print_subsection "Running configuration validation"
        
        if [ "$DRY_RUN" = true ]; then
            print_warning "DRY RUN: Would run configuration validation"
            return 0
        fi
        
        if bash "$validation_script" --quiet; then
            print_success "Environment configuration validation passed"
        else
            print_error "Environment configuration validation failed"
            if [ "$INTERACTIVE_MODE" = true ]; then
                read -p "Continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    error_exit "Environment setup aborted due to validation failure"
                fi
            else
                error_exit "Environment setup failed validation"
            fi
        fi
    else
        print_warning "Configuration validation script not found, skipping"
    fi
}

generate_setup_summary() {
    print_section "Environment Setup Summary"
    
    echo "Environment Configuration Complete!"
    echo
    echo "Deployment Type: $DEPLOYMENT_TYPE"
    echo "Project Root: $PROJECT_ROOT"
    echo "Global Environment: $GLOBAL_ENV_FILE"
    echo
    
    # Count configured services
    local service_count=0
    while IFS= read -r -d '' env_file; do
        ((service_count++))
    done < <(find "$COMPOSITIONS_DIR" -name ".env" -type f -print0 2>/dev/null || true)
    
    echo "Configured Services: $service_count"
    echo
    
    # Show next steps
    echo "Next Steps:"
    echo "1. Review and customize environment files as needed"
    echo "2. Deploy services using: docker/scripts/deploy-project.sh"
    echo "3. Monitor services using: docker/scripts/monitor.sh"
    echo "4. Check health using: docker/scripts/health-check.sh"
    echo
    
    if [ "$DEPLOYMENT_TYPE" = "production" ]; then
        echo "Production Environment Notes:"
        echo "- Ensure all security settings are properly configured"
        echo "- Set up automated backups"
        echo "- Configure monitoring and alerting"
        echo "- Review firewall and network settings"
        echo
    fi
    
    echo "Log file: $LOG_FILE"
}

# ==============================================================================
# Interactive Setup Functions
# ==============================================================================

interactive_setup() {
    print_header
    
    echo "This script will help you set up the environment for your"
    echo "Synology NAS Docker management project."
    echo
    
    # Confirm deployment type
    echo "Current deployment type: $DEPLOYMENT_TYPE"
    read -p "Is this correct? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        DEPLOYMENT_TYPE=""
        detect_deployment_type
    fi
    
    # Advanced options
    read -p "Do you want to configure advanced options? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        configure_advanced_options
    fi
    
    # Confirmation
    echo
    echo "Setup Configuration:"
    echo "- Deployment Type: $DEPLOYMENT_TYPE"
    echo "- Force Overwrite: $FORCE_OVERWRITE"
    echo "- Backup Existing: $BACKUP_EXISTING"
    echo "- Validate Config: $VALIDATE_CONFIG"
    echo "- Setup Services: $SETUP_SERVICES"
    echo
    
    read -p "Proceed with environment setup? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log "INFO" "Environment setup cancelled by user"
        exit 0
    fi
}

configure_advanced_options() {
    echo
    echo "Advanced Options:"
    
    # Force overwrite
    read -p "Force overwrite existing files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        FORCE_OVERWRITE=true
    fi
    
    # Backup existing
    read -p "Backup existing configuration files? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        BACKUP_EXISTING=false
    fi
    
    # Validate config
    read -p "Validate configuration after setup? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        VALIDATE_CONFIG=false
    fi
    
    # Setup services
    read -p "Setup service-specific environments? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        SETUP_SERVICES=false
    fi
}

# ==============================================================================
# Main Execution Functions
# ==============================================================================

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Automate environment configuration for Synology NAS Docker management project.

OPTIONS:
    -t, --type TYPE         Deployment type (development|staging|production)
    -f, --force             Force overwrite existing files
    -n, --no-backup         Skip backing up existing configuration
    -s, --skip-validation   Skip configuration validation
    -q, --quiet             Non-interactive mode
    --no-services           Skip service-specific environment setup
    --dry-run               Show what would be done without making changes
    -h, --help              Show this help message

EXAMPLES:
    # Interactive setup
    $SCRIPT_NAME

    # Development environment setup
    $SCRIPT_NAME --type development

    # Production setup with force overwrite
    $SCRIPT_NAME --type production --force

    # Quiet mode for automation
    $SCRIPT_NAME --type staging --quiet

    # Dry run to see what would be done
    $SCRIPT_NAME --type production --dry-run

DEPLOYMENT TYPES:
    development    - Local development with debug enabled
    staging        - Testing environment with monitoring
    production     - Live environment with security focus

FILES CREATED:
    .env                        - Global environment configuration
    docker/compositions/*/.env  - Service-specific configurations

For more information, see the project documentation.
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                DEPLOYMENT_TYPE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_OVERWRITE=true
                shift
                ;;
            -n|--no-backup)
                BACKUP_EXISTING=false
                shift
                ;;
            -s|--skip-validation)
                VALIDATE_CONFIG=false
                shift
                ;;
            -q|--quiet)
                INTERACTIVE_MODE=false
                shift
                ;;
            --no-services)
                SETUP_SERVICES=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Validate deployment type if provided
    if [ -n "$DEPLOYMENT_TYPE" ]; then
        case "$DEPLOYMENT_TYPE" in
            development|staging|production)
                ;;
            *)
                error_exit "Invalid deployment type: $DEPLOYMENT_TYPE"
                ;;
        esac
    fi
}

main() {
    # Setup error handling
    trap 'error_exit "Script interrupted"' INT TERM
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Start logging
    log "INFO" "Starting environment setup script"
    log "INFO" "Script version: 1.0.0"
    log "INFO" "Project root: $PROJECT_ROOT"
    
    # Interactive setup if no deployment type specified
    if [ -z "$DEPLOYMENT_TYPE" ] && [ "$INTERACTIVE_MODE" = true ]; then
        interactive_setup
    fi
    
    # Main execution flow
    check_prerequisites
    detect_deployment_type
    backup_existing_config
    create_global_environment
    setup_service_environments
    validate_environment
    generate_setup_summary
    
    log "INFO" "Environment setup completed successfully"
    
    if [ "$DRY_RUN" = true ]; then
        echo
        print_warning "This was a dry run. No files were actually modified."
    fi
}

# Execute main function with all arguments
main "$@"