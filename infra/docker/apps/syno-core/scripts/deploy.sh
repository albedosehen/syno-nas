#!/bin/bash

# ===========================================
# CORE SERVICES DEPLOYMENT SCRIPT
# ===========================================

set -e

# Determine script and project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
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

# Compose file mapping
get_compose_files() {
    case $1 in
        base)
            echo "$PROJECT_DIR/docker-compose.base.yml"
            ;;
        secrets)
            echo "$PROJECT_DIR/docker-compose.base.yml $PROJECT_DIR/docker-compose.secrets.yml"
            ;;
        database)
            echo "$PROJECT_DIR/docker-compose.base.yml $PROJECT_DIR/docker-compose.secrets.yml $PROJECT_DIR/docker-compose.database.yml"
            ;;
        management)
            echo "$PROJECT_DIR/docker-compose.base.yml $PROJECT_DIR/docker-compose.secrets.yml $PROJECT_DIR/docker-compose.management.yml"
            ;;
        all)
            echo "$PROJECT_DIR/docker-compose.yml"
            ;;
    esac
}

# Usage information
usage() {
    echo "Usage: $0 [OPTION] [ACTION]"
    echo ""
    echo "Modular deployment options:"
    echo "  base        - Deploy base infrastructure (networks, volumes)"
    echo "  secrets     - Deploy secrets management (Doppler)"
    echo "  database    - Deploy database services (SurrealDB + backup)"
    echo "  management  - Deploy management UI (Portainer)"
    echo "  all         - Deploy complete stack"
    echo ""
    echo "Actions:"
    echo "  up          - Start services (default)"
    echo "  down        - Stop services"
    echo "  restart     - Restart services"
    echo "  logs        - View logs"
    echo "  status      - Show service status"
    echo ""
    echo "Examples:"
    echo "  $0 base up            # Deploy base infrastructure"
    echo "  $0 secrets            # Deploy secrets (up is default)"
    echo "  $0 database logs      # View database logs"
    echo "  $0 all down           # Stop everything"
    echo "  $0 management restart # Restart management services"
}

# Parse arguments
MODULE=${1:-all}
ACTION=${2:-up}

# Validate module
case $MODULE in
    base|secrets|database|management|all)
        ;;
    help|--help|-h)
        usage
        exit 0
        ;;
    *)
        log_error "Invalid module: $MODULE"
        usage
        exit 1
        ;;
esac

# Validate action
case $ACTION in
    up|down|restart|logs|status)
        ;;
    *)
        log_error "Invalid action: $ACTION"
        usage
        exit 1
        ;;
esac


# Get services for a module (used for service-specific operations)
get_module_services() {
    case $1 in
        base)
            echo ""
            ;;
        secrets)
            echo "doppler"
            ;;
        database)
            echo "surrealdb surrealdb-backup"
            ;;
        management)
            echo "portainer"
            ;;
        all)
            echo ""
            ;;
    esac
}

# Execute deployment
deploy() {
    local module=$1
    local action=$2
    local compose_files=$(get_compose_files $module)
    local services=$(get_module_services $module)
    
    log_info "Executing: $action for module: $module"
    
    # Change to project directory to ensure correct context
    cd "$PROJECT_DIR"
    
    # Build docker compose command based on module type
    local compose_cmd
    if [ "$module" = "all" ]; then
        compose_cmd="docker compose -f $compose_files"
    else
        compose_cmd="docker compose $(echo $compose_files | sed 's/\([^ ]*\)/-f \1/g')"
    fi
    
    case $action in
        up)
            log_info "Starting $module services..."
            if [ -n "$services" ]; then
                eval "$compose_cmd up -d $services"
            else
                eval "$compose_cmd up -d"
            fi
            log_success "$module services started successfully"
            ;;
        down)
            log_info "Stopping $module services..."
            if [ -n "$services" ] && [ "$module" != "all" ]; then
                eval "$compose_cmd stop $services"
                eval "$compose_cmd rm -f $services"
            else
                eval "$compose_cmd down"
            fi
            log_success "$module services stopped successfully"
            ;;
        restart)
            log_info "Restarting $module services..."
            if [ -n "$services" ]; then
                eval "$compose_cmd restart $services"
            else
                eval "$compose_cmd restart"
            fi
            log_success "$module services restarted successfully"
            ;;
        logs)
            log_info "Showing logs for $module services..."
            if [ -n "$services" ]; then
                eval "$compose_cmd logs -f $services"
            else
                eval "$compose_cmd logs -f"
            fi
            ;;
        status)
            log_info "Status for $module services:"
            if [ -n "$services" ]; then
                eval "$compose_cmd ps $services"
            else
                eval "$compose_cmd ps"
            fi
            ;;
    esac
}

# Main execution
log_info "Core Services Modular Deployment"
log_info "Module: $MODULE | Action: $ACTION"
echo ""

deploy $MODULE $ACTION