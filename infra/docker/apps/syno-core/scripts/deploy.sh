#!/bin/bash

# ===========================================
# CORE SERVICES DEPLOYMENT SCRIPT
# ===========================================
# Helper script for modular deployment options

set -e

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

# Usage information
usage() {
    echo "Usage: $0 [OPTION] [ACTION]"
    echo ""
    echo "Modular deployment options:"
    echo "  base        - Deploy base infrastructure (networks, volumes)"
    echo "  secrets     - Deploy secrets management (Doppler)"
    echo "  database    - Deploy database services (SurrealDB)"
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

# Compose file mapping
get_compose_files() {
    case $1 in
        base)
            echo "docker-compose.base.yml"
            ;;
        secrets)
            echo "docker-compose.base.yml docker-compose.secrets.yml"
            ;;
        database)
            echo "docker-compose.base.yml docker-compose.secrets.yml docker-compose.database.yml"
            ;;
        management)
            echo "docker-compose.base.yml docker-compose.secrets.yml docker-compose.management.yml"
            ;;
        all)
            echo "docker-compose.yml"
            ;;
    esac
}

# Execute deployment
deploy() {
    local module=$1
    local action=$2
    local compose_files=$(get_compose_files $module)
    
    log_info "Executing: $action for module: $module"
    
    case $action in
        up)
            log_info "Starting $module services..."
            if [ "$module" = "all" ]; then
                docker compose -f $compose_files up -d
            else
                docker compose $(echo $compose_files | sed 's/\([^ ]*\)/-f \1/g') up -d
            fi
            log_success "$module services started successfully"
            ;;
        down)
            log_info "Stopping $module services..."
            if [ "$module" = "all" ]; then
                docker compose -f $compose_files down
            else
                docker compose $(echo $compose_files | sed 's/\([^ ]*\)/-f \1/g') down
            fi
            log_success "$module services stopped successfully"
            ;;
        restart)
            log_info "Restarting $module services..."
            if [ "$module" = "all" ]; then
                docker compose -f $compose_files restart
            else
                docker compose $(echo $compose_files | sed 's/\([^ ]*\)/-f \1/g') restart
            fi
            log_success "$module services restarted successfully"
            ;;
        logs)
            log_info "Showing logs for $module services..."
            if [ "$module" = "all" ]; then
                docker compose -f $compose_files logs -f
            else
                docker compose $(echo $compose_files | sed 's/\([^ ]*\)/-f \1/g') logs -f
            fi
            ;;
        status)
            log_info "Status for $module services:"
            if [ "$module" = "all" ]; then
                docker compose -f $compose_files ps
            else
                docker compose $(echo $compose_files | sed 's/\([^ ]*\)/-f \1/g') ps
            fi
            ;;
    esac
}

# Main execution
log_info "Core Services Modular Deployment"
log_info "Module: $MODULE | Action: $ACTION"
echo ""

deploy $MODULE $ACTION