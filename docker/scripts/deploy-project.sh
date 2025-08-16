#!/bin/bash

# Synology NAS Docker Management - Project Deployment Script
# This script automates the deployment of the entire Docker management project
# with proper configuration, prerequisites checking, and service orchestration

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="syno-nas-docker-management"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_EXAMPLE_FILE="$PROJECT_ROOT/.env.example"

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
    echo "Synology NAS Docker Management - Project Deployment Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --category CATEGORY      Deploy only services in specified category"
    echo "                               (management, media, productivity, networking)"
    echo "  -s, --service SERVICE        Deploy only specified service"
    echo "  -p, --parallel              Enable parallel service deployment"
    echo "  -f, --force                 Force deployment even if services exist"
    echo "  --skip-portainer            Skip Portainer deployment"
    echo "  --skip-network              Skip network creation"
    echo "  --dry-run                   Show what would be deployed without executing"
    echo "  --verbose                   Enable verbose output"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          Deploy all services"
    echo "  $0 -c management            Deploy only management services"
    echo "  $0 -s portainer             Deploy only Portainer"
    echo "  $0 -p                       Deploy all services in parallel"
    echo "  $0 --dry-run                Show deployment plan without executing"
    echo ""
}

# Parse command line arguments
DEPLOY_CATEGORY=""
DEPLOY_SERVICE=""
PARALLEL_DEPLOYMENT=false
FORCE_DEPLOYMENT=false
SKIP_PORTAINER=false
SKIP_NETWORK=false
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--category)
            DEPLOY_CATEGORY="$2"
            shift 2
            ;;
        -s|--service)
            DEPLOY_SERVICE="$2"
            shift 2
            ;;
        -p|--parallel)
            PARALLEL_DEPLOYMENT=true
            shift
            ;;
        -f|--force)
            FORCE_DEPLOYMENT=true
            shift
            ;;
        --skip-portainer)
            SKIP_PORTAINER=true
            shift
            ;;
        --skip-network)
            SKIP_NETWORK=true
            shift
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

# Load global environment variables
load_global_config() {
    if [ -f "$ENV_FILE" ]; then
        log_info "Loading global configuration from $ENV_FILE"
        source "$ENV_FILE"
    else
        log_warning "Global .env file not found, using defaults"
    fi
    
    # Set defaults for critical variables
    PUID=${PUID:-1000}
    PGID=${PGID:-1000}
    TZ=${TZ:-UTC}
    DOCKER_NETWORK_NAME=${DOCKER_NETWORK_NAME:-syno-nas-network}
    PARALLEL_OPERATIONS=${PARALLEL_OPERATIONS:-true}
    MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-4}
    VERBOSE_OUTPUT=${VERBOSE_OUTPUT:-false}
    DRY_RUN_MODE=${DRY_RUN_MODE:-false}
}

# Enhanced logging with verbose mode
verbose_log() {
    if [ "$VERBOSE" = true ] || [ "$VERBOSE_OUTPUT" = true ]; then
        log_info "VERBOSE: $1"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if Docker is running
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check if Docker Compose is available
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    # Check if running on Synology (optional warning)
    if [ ! -d "/volume1" ]; then
        log_warning "This doesn't appear to be a Synology NAS system"
        log_warning "Some paths and permissions may need adjustment"
    fi
    
    # Check available disk space
    local available_space=$(df "$PROJECT_ROOT" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1048576 ]; then  # Less than 1GB
        log_warning "Low disk space detected. Ensure sufficient space for Docker images and data"
    fi
    
    log_success "Prerequisites check passed"
}

# Setup global environment
setup_global_environment() {
    log_step "Setting up global environment..."
    
    cd "$PROJECT_ROOT"
    
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$ENV_EXAMPLE_FILE" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would copy $ENV_EXAMPLE_FILE to $ENV_FILE"
            else
                cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
                log_success "Created global .env file from .env.example"
                log_warning "Please review and customize the global .env file"
                
                # Prompt user to edit the file in interactive mode
                if [ -t 0 ] && [ "$DRY_RUN" = false ]; then
                    read -p "Do you want to edit the global .env file now? (y/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        ${EDITOR:-nano} "$ENV_FILE"
                        log_info "Please run the script again after configuring the environment"
                        exit 0
                    fi
                fi
            fi
        else
            log_error "Global .env.example file not found"
            exit 1
        fi
    else
        log_info "Global .env file already exists"
    fi
    
    # Reload configuration after potential changes
    load_global_config
}

# Create global directories
create_global_directories() {
    log_step "Creating global directories..."
    
    local directories=(
        "${DATA_BASE_PATH:-/volume1/docker/data}"
        "${BACKUP_BASE_PATH:-/volume1/docker/backups}"
        "$PROJECT_ROOT/logs"
    )
    
    for dir in "${directories[@]}"; do
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would create directory: $dir"
        else
            if [ ! -d "$dir" ]; then
                mkdir -p "$dir"
                verbose_log "Created directory: $dir"
            fi
            
            # Set proper permissions
            if [ -n "$PUID" ] && [ -n "$PGID" ]; then
                chown -R "$PUID:$PGID" "$dir" 2>/dev/null || log_warning "Could not set ownership for $dir"
            fi
            chmod -R 755 "$dir" 2>/dev/null || log_warning "Could not set permissions for $dir"
        fi
    done
    
    log_success "Global directories created and configured"
}

# Create Docker network
create_docker_network() {
    if [ "$SKIP_NETWORK" = true ]; then
        log_info "Skipping Docker network creation"
        return 0
    fi
    
    log_step "Creating Docker network: $DOCKER_NETWORK_NAME"
    
    if docker network ls | grep -q "$DOCKER_NETWORK_NAME"; then
        log_info "Docker network '$DOCKER_NETWORK_NAME' already exists"
    else
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would create Docker network: $DOCKER_NETWORK_NAME"
        else
            docker network create "$DOCKER_NETWORK_NAME" --driver bridge
            log_success "Created Docker network: $DOCKER_NETWORK_NAME"
        fi
    fi
}

# Discover available services
discover_services() {
    local category="${1:-all}"
    local services=()
    
    verbose_log "Discovering services in category: $category"
    
    if [ "$category" = "all" ]; then
        # Find all docker-compose.yml files in compositions directory
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

# Deploy single service
deploy_service() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_service "Deploying $category/$service_name"
    
    if [ ! -f "$service_dir/docker-compose.yml" ]; then
        log_error "No docker-compose.yml found in $service_dir"
        return 1
    fi
    
    cd "$service_dir"
    
    # Check if service deployment script exists
    if [ -f "./deploy.sh" ] && [ -x "./deploy.sh" ]; then
        verbose_log "Using service-specific deployment script"
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would execute ./deploy.sh"
        else
            ./deploy.sh
        fi
    else
        # Generic deployment process
        verbose_log "Using generic deployment process"
        
        # Setup service environment
        if [ ! -f ".env" ] && [ -f ".env.example" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would copy .env.example to .env"
            else
                cp .env.example .env
                log_info "Created .env from .env.example for $service_name"
            fi
        fi
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would execute docker-compose up -d"
        else
            # Pull images and deploy
            docker-compose pull
            docker-compose up -d
        fi
    fi
    
    log_success "Deployed $category/$service_name"
    return 0
}

# Deploy services in parallel
deploy_services_parallel() {
    local services=("$@")
    local pids=()
    local max_jobs=${MAX_PARALLEL_JOBS:-4}
    
    log_info "Deploying ${#services[@]} services in parallel (max $max_jobs jobs)"
    
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
        
        # Start service deployment in background
        deploy_service "$service" &
        pids+=($!)
    done
    
    # Wait for all remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Deploy services sequentially
deploy_services_sequential() {
    local services=("$@")
    
    log_info "Deploying ${#services[@]} services sequentially"
    
    for service in "${services[@]}"; do
        deploy_service "$service"
    done
}

# Wait for service health
wait_for_service_health() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local timeout="${2:-120}"
    
    log_info "Waiting for $service_name to be healthy..."
    
    cd "$service_dir"
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        # Check if containers are running
        if docker-compose ps | grep -q "Up\|healthy"; then
            verbose_log "$service_name appears to be running"
            return 0
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    log_warning "$service_name did not become healthy within $timeout seconds"
    return 1
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    local services
    if [ -n "$DEPLOY_SERVICE" ]; then
        services=("$COMPOSITIONS_DIR/*/$DEPLOY_SERVICE")
    elif [ -n "$DEPLOY_CATEGORY" ]; then
        services=($(discover_services "$DEPLOY_CATEGORY"))
    else
        services=($(discover_services "all"))
    fi
    
    local failed_services=()
    
    for service_dir in "${services[@]}"; do
        if [ -d "$service_dir" ]; then
            local service_name=$(basename "$service_dir")
            
            cd "$service_dir"
            
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would verify $service_name"
                continue
            fi
            
            # Check if containers are running
            if docker-compose ps | grep -q "Up"; then
                log_success "$service_name is running"
                verbose_log "Waiting for $service_name health check..."
                wait_for_service_health "$service_dir" 30
            else
                log_error "$service_name is not running"
                failed_services+=("$service_name")
            fi
        fi
    done
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log_success "All services are running successfully"
    else
        log_error "Failed services: ${failed_services[*]}"
        return 1
    fi
}

# Display deployment summary
show_deployment_summary() {
    log_step "Deployment Summary"
    echo "========================================"
    
    # Project information
    echo "Project: $PROJECT_NAME"
    echo "Location: $PROJECT_ROOT"
    echo "Network: $DOCKER_NETWORK_NAME"
    echo ""
    
    # Deployed services
    echo "Deployed Services:"
    
    local services
    if [ -n "$DEPLOY_SERVICE" ]; then
        services=("$COMPOSITIONS_DIR/*/$DEPLOY_SERVICE")
    elif [ -n "$DEPLOY_CATEGORY" ]; then
        services=($(discover_services "$DEPLOY_CATEGORY"))
    else
        services=($(discover_services "all"))
    fi
    
    for service_dir in "${services[@]}"; do
        if [ -d "$service_dir" ]; then
            local service_name=$(basename "$service_dir")
            local category=$(basename "$(dirname "$service_dir")")
            
            cd "$service_dir"
            
            if [ "$DRY_RUN" = true ]; then
                echo "  - $category/$service_name (DRY RUN)"
            else
                local status="Stopped"
                if docker-compose ps | grep -q "Up"; then
                    status="Running"
                fi
                echo "  - $category/$service_name: $status"
            fi
        fi
    done
    
    echo ""
    echo "Management URLs:"
    if [ "$SKIP_PORTAINER" = false ] && [ -z "$DEPLOY_SERVICE" -o "$DEPLOY_SERVICE" = "portainer" ]; then
        local portainer_port=$(grep -E "^PORTAINER_PORT=" "$COMPOSITIONS_DIR/management/portainer/.env" 2>/dev/null | cut -d= -f2 || echo "9000")
        echo "  - Portainer: http://$(hostname -I | awk '{print $1}'):${portainer_port}"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Access the Portainer web interface to manage containers"
    echo "2. Review service logs: docker-compose logs -f <service>"
    echo "3. Monitor system resources and container health"
    echo "4. Set up automated backups and monitoring"
    echo ""
}

# Main deployment process
main() {
    echo "========================================"
    echo "  Synology NAS Docker Management"
    echo "     Project Deployment Script"
    echo "========================================"
    echo ""
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Load configuration first
    load_global_config
    
    # Apply CLI overrides
    if [ "$DRY_RUN" = true ]; then
        DRY_RUN_MODE=true
    fi
    if [ "$VERBOSE" = true ]; then
        VERBOSE_OUTPUT=true
    fi
    
    if [ "$DRY_RUN_MODE" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_global_environment
    create_global_directories
    create_docker_network
    
    # Determine services to deploy
    local services_to_deploy=()
    
    if [ -n "$DEPLOY_SERVICE" ]; then
        # Deploy specific service
        local service_path="$COMPOSITIONS_DIR/*/$DEPLOY_SERVICE"
        for path in $service_path; do
            if [ -d "$path" ]; then
                services_to_deploy+=("$path")
                break
            fi
        done
        
        if [ ${#services_to_deploy[@]} -eq 0 ]; then
            log_error "Service '$DEPLOY_SERVICE' not found"
            exit 1
        fi
    elif [ -n "$DEPLOY_CATEGORY" ]; then
        # Deploy category services
        services_to_deploy=($(discover_services "$DEPLOY_CATEGORY"))
        
        if [ ${#services_to_deploy[@]} -eq 0 ]; then
            log_error "No services found in category '$DEPLOY_CATEGORY'"
            exit 1
        fi
    else
        # Deploy all services, prioritize management services
        local mgmt_services=($(discover_services "management"))
        local other_services=($(discover_services "all"))
        
        # Filter out management services from other_services
        local filtered_services=()
        for service in "${other_services[@]}"; do
            local is_mgmt=false
            for mgmt_service in "${mgmt_services[@]}"; do
                if [ "$service" = "$mgmt_service" ]; then
                    is_mgmt=true
                    break
                fi
            done
            if [ "$is_mgmt" = false ]; then
                filtered_services+=("$service")
            fi
        done
        
        # Deploy management services first, then others
        services_to_deploy=("${mgmt_services[@]}" "${filtered_services[@]}")
    fi
    
    log_info "Found ${#services_to_deploy[@]} services to deploy"
    
    # Deploy services
    if [ ${#services_to_deploy[@]} -gt 0 ]; then
        if [ "$PARALLEL_DEPLOYMENT" = true ] && [ "$PARALLEL_OPERATIONS" = true ] && [ ${#services_to_deploy[@]} -gt 1 ]; then
            deploy_services_parallel "${services_to_deploy[@]}"
        else
            deploy_services_sequential "${services_to_deploy[@]}"
        fi
        
        # Verify deployment
        if [ "$DRY_RUN_MODE" = false ]; then
            sleep 5  # Give services time to start
            verify_deployment
        fi
    else
        log_warning "No services found to deploy"
    fi
    
    # Show summary
    show_deployment_summary
    
    if [ "$DRY_RUN_MODE" = false ]; then
        log_success "Project deployment completed successfully!"
    else
        log_info "DRY RUN completed - no changes were made"
    fi
}

# Error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Execute main function
main "$@"