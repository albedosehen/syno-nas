#!/bin/bash

# Portainer Deployment Script for Synology NAS
# This script automates the deployment of Portainer with proper configuration

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="portainer"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
ENV_EXAMPLE_FILE=".env.example"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
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
    
    log_success "Prerequisites check passed"
}

# Setup environment file
setup_environment() {
    log_info "Setting up environment configuration..."
    
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$ENV_EXAMPLE_FILE" ]; then
            cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
            log_success "Created .env file from .env.example"
            log_warning "Please review and customize the .env file before proceeding"
            
            # Prompt user to edit the file
            read -p "Do you want to edit the .env file now? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                ${EDITOR:-nano} "$ENV_FILE"
            fi
        else
            log_error ".env.example file not found"
            exit 1
        fi
    else
        log_info ".env file already exists"
    fi
}

# Create necessary directories
create_directories() {
    log_info "Creating necessary directories..."
    
    # Source the environment file to get variables
    source "$ENV_FILE"
    
    # Create data directory if it doesn't exist
    if [ ! -d "data" ]; then
        mkdir -p data
        log_success "Created data directory"
    fi
    
    # Set proper permissions
    if [ -n "$PUID" ] && [ -n "$PGID" ]; then
        if command -v chown &> /dev/null; then
            chown -R "$PUID:$PGID" data 2>/dev/null || log_warning "Could not set ownership, you may need to run with sudo"
        fi
        chmod -R 755 data
        log_success "Set directory permissions"
    fi
}

# Check for port conflicts
check_ports() {
    log_info "Checking for port conflicts..."
    
    # Source the environment file to get variables
    source "$ENV_FILE"
    
    # Check if ports are in use
    if netstat -tuln 2>/dev/null | grep -q ":${PORTAINER_PORT:-9000} "; then
        log_error "Port ${PORTAINER_PORT:-9000} is already in use"
        log_info "Please change PORTAINER_PORT in .env file or stop the service using this port"
        exit 1
    fi
    
    if netstat -tuln 2>/dev/null | grep -q ":${PORTAINER_EDGE_PORT:-8000} "; then
        log_error "Port ${PORTAINER_EDGE_PORT:-8000} is already in use"
        log_info "Please change PORTAINER_EDGE_PORT in .env file or stop the service using this port"
        exit 1
    fi
    
    log_success "Port check passed"
}

# Deploy Portainer
deploy_portainer() {
    log_info "Deploying Portainer..."
    
    # Pull latest images
    log_info "Pulling latest Portainer image..."
    docker-compose pull
    
    # Start the services
    log_info "Starting Portainer services..."
    docker-compose up -d
    
    log_success "Portainer deployed successfully"
}

# Wait for service to be ready
wait_for_service() {
    log_info "Waiting for Portainer to be ready..."
    
    # Source the environment file to get variables
    source "$ENV_FILE"
    
    local port="${PORTAINER_PORT:-9000}"
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:$port" > /dev/null 2>&1; then
            log_success "Portainer is ready and responding"
            return 0
        fi
        
        log_info "Waiting for Portainer to start (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done
    
    log_error "Portainer did not become ready within expected time"
    log_info "Check the logs with: docker-compose logs portainer"
    return 1
}

# Display deployment summary
show_summary() {
    log_info "Deployment Summary"
    echo "===================="
    
    # Source the environment file to get variables
    source "$ENV_FILE"
    
    local port="${PORTAINER_PORT:-9000}"
    local edge_port="${PORTAINER_EDGE_PORT:-8000}"
    
    echo "Service: Portainer Community Edition"
    echo "Status: $(docker-compose ps --services --filter status=running | grep -q portainer && echo "Running" || echo "Not Running")"
    echo "Web Interface: http://$(hostname -I | awk '{print $1}'):$port"
    echo "Edge Port: $edge_port"
    echo "Data Directory: $(pwd)/data"
    echo ""
    echo "Next Steps:"
    echo "1. Open your web browser and navigate to the Web Interface URL above"
    echo "2. Create your initial administrator account"
    echo "3. Select 'Local' environment to manage this Docker instance"
    echo ""
    echo "Management Commands:"
    echo "- View logs: docker-compose logs portainer"
    echo "- Stop service: docker-compose stop"
    echo "- Start service: docker-compose start"
    echo "- Restart service: docker-compose restart"
    echo "- Update service: ./update.sh (if available)"
    echo ""
}

# Main deployment process
main() {
    echo "========================================"
    echo "    Portainer Deployment Script"
    echo "========================================"
    echo ""
    
    cd "$SCRIPT_DIR"
    
    check_prerequisites
    setup_environment
    create_directories
    check_ports
    deploy_portainer
    
    if wait_for_service; then
        show_summary
        log_success "Portainer deployment completed successfully!"
    else
        log_error "Deployment completed but service may not be fully ready"
        log_info "Check logs with: docker-compose logs portainer"
    fi
}

# Handle script arguments
case "${1:-}" in
    "help"|"--help"|"-h")
        echo "Portainer Deployment Script"
        echo ""
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  help, --help, -h    Show this help message"
        echo "  status              Show current status"
        echo "  logs                Show service logs"
        echo ""
        echo "Default behavior: Deploy Portainer service"
        exit 0
        ;;
    "status")
        cd "$SCRIPT_DIR"
        echo "Portainer Status:"
        docker-compose ps
        exit 0
        ;;
    "logs")
        cd "$SCRIPT_DIR"
        docker-compose logs portainer
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac