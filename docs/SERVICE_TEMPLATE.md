# Service Template Guide

This guide provides templates and patterns for adding new services to the Synology NAS Docker Management project. All new services should follow these established patterns for consistency and maintainability.

## Table of Contents

- [Service Directory Structure](#service-directory-structure)
- [Template Files](#template-files)
- [Environment Configuration](#environment-configuration)
- [Documentation Standards](#documentation-standards)
- [Deployment Scripts](#deployment-scripts)
- [Backup Procedures](#backup-procedures)
- [Testing and Validation](#testing-and-validation)

## Service Directory Structure

Every service should follow this standardized directory structure:

```
docker/compositions/[category]/[service-name]/
├── README.md                 # Comprehensive service documentation
├── docker-compose.yml        # Service definition
├── .env.example              # Environment template with documentation
├── .env                      # Actual environment (git-ignored)
├── deploy.sh                 # Deployment automation script
├── backup.sh                 # Backup automation script
├── data/                     # Persistent data directory (git-ignored)
└── config/                   # Configuration files (optional)
    ├── app.conf.example
    └── other-config.example
```

### Category Organization

Services are organized into logical categories:

- **`management/`**: Docker management tools (Portainer, monitoring)
- **`media/`**: Media servers and *arr services (Plex, Jellyfin, Sonarr, Radarr)
- **`productivity/`**: Productivity applications (NextCloud, collaboration tools)
- **`networking/`**: Network services (VPN, proxy, DNS)
- **`security/`**: Security tools (monitoring, intrusion detection)
- **`backup/`**: Backup and sync services
- **`development/`**: Development tools (Git, CI/CD)

## Template Files

### docker-compose.yml Template

```yaml
# Template: docker-compose.yml
# Replace [SERVICE_NAME], [CATEGORY], and [DESCRIPTION] with actual values

services:
  [service-name]:
    image: [official/image:tag]
    container_name: [service-name]
    restart: unless-stopped
    
    # Environment variables
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-UTC}
      # Add service-specific environment variables here
      
    # Port mapping - local network access only by default
    ports:
      - "${[SERVICE_NAME]_PORT:-[default-port]}:[container-port]"
      
    # Volume mappings optimized for Synology NAS
    volumes:
      # Configuration persistence
      - ${[SERVICE_NAME]_CONFIG_PATH:-./config}:/app/config
      # Data persistence
      - ${[SERVICE_NAME]_DATA_PATH:-./data}:/app/data
      # Optional: Media access (for media services)
      # - ${MEDIA_PATH:-/volume1/media}:/media:ro
      # Optional: Downloads access
      # - ${DOWNLOADS_PATH:-/volume1/downloads}:/downloads
      
    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:[container-port]/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
      
    # Resource limits
    deploy:
      resources:
        limits:
          memory: ${[SERVICE_NAME]_MEMORY_LIMIT:-512M}
        reservations:
          memory: ${[SERVICE_NAME]_MEMORY_RESERVATION:-256M}
          
    # Network configuration
    networks:
      - [service-name]_network
      
    # Labels for organization and management
    labels:
      - "traefik.enable=false"  # Disable external access through reverse proxy
      - "com.synology.[service-name].description=[Service Description]"
      - "com.synology.[service-name].category=[category]"

# Networks
networks:
  [service-name]_network:
    driver: bridge
    name: [service-name]_network

# Volumes (if using named volumes)
volumes:
  [service-name]_data:
    name: [service-name]_data
    driver: local
  [service-name]_config:
    name: [service-name]_config
    driver: local
```

### .env.example Template

```env
# [Service Name] Configuration
# Copy this file to .env and customize the values for your Synology NAS setup

# ==========================================
# SYSTEM CONFIGURATION
# ==========================================

# User and Group IDs for proper permissions on Synology NAS
# Run 'id' command on your NAS to get these values
PUID=1000
PGID=1000

# Timezone configuration
# Use your local timezone (e.g., America/New_York, Europe/London, Asia/Tokyo)
TZ=UTC

# ==========================================
# [SERVICE_NAME] NETWORK CONFIGURATION
# ==========================================

# [Service Name] port (default: [default-port])
# This is the main interface for accessing [Service Name]
[SERVICE_NAME]_PORT=[default-port]

# Additional ports (if needed)
# [SERVICE_NAME]_ADDITIONAL_PORT=[port]

# ==========================================
# STORAGE CONFIGURATION
# ==========================================

# [Service Name] configuration directory
# This directory will store [Service Name]'s configuration files
# Use absolute path for production deployments
# Example for Synology: /volume1/docker/[service-name]/config
[SERVICE_NAME]_CONFIG_PATH=./config

# [Service Name] data directory
# This directory will store [Service Name]'s persistent data
# Use absolute path for production deployments
# Example for Synology: /volume1/docker/[service-name]/data
[SERVICE_NAME]_DATA_PATH=./data

# ==========================================
# SYNOLOGY NAS SPECIFIC SETTINGS
# ==========================================

# Media path (for media services)
# MEDIA_PATH=/volume1/media

# Downloads path (for download managers)
# DOWNLOADS_PATH=/volume1/downloads

# Docker volumes path on Synology NAS
# This allows [Service Name] to access other container volumes if needed
SYNOLOGY_DOCKER_PATH=/volume1/docker

# ==========================================
# SECURITY SETTINGS
# ==========================================

# Network access restriction
# Set to 'true' to restrict access to local network only
# Set to 'false' if you need external access (NOT RECOMMENDED)
LOCAL_NETWORK_ONLY=true

# ==========================================
# RESOURCE LIMITS
# ==========================================

# Memory limits for [Service Name] container
[SERVICE_NAME]_MEMORY_LIMIT=512M
[SERVICE_NAME]_MEMORY_RESERVATION=256M

# ==========================================
# SERVICE-SPECIFIC CONFIGURATION
# ==========================================

# Add service-specific environment variables here
# [SERVICE_NAME]_SETTING=value
# [SERVICE_NAME]_FEATURE_ENABLED=true

# ==========================================
# BACKUP CONFIGURATION
# ==========================================

# Backup directory for [Service Name] data
# Recommended to use a different volume for backups
BACKUP_PATH=/volume1/docker/backups/[service-name]
```

### deploy.sh Template

```bash
#!/bin/bash
# [Service Name] Deployment Script
# Automated deployment for [Service Name] on Synology NAS

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="[service-name]"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

# Functions
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

# Pre-deployment checks
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose > /dev/null 2>&1; then
        log_error "docker-compose is not installed or not in PATH."
        exit 1
    fi
    
    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment..."
    
    # Create .env file if it doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$ENV_EXAMPLE" ]; then
            cp "$ENV_EXAMPLE" "$ENV_FILE"
            log_warning ".env file created from template. Please review and customize it."
            log_info "Edit the .env file with your settings, then run this script again."
            exit 0
        else
            log_error "No .env file found and no .env.example template available."
            exit 1
        fi
    fi
    
    # Create data directories
    mkdir -p data config
    
    # Set proper permissions
    if [ -d "data" ]; then
        chmod 755 data
        if command -v id > /dev/null 2>&1; then
            chown $(id -u):$(id -g) data 2>/dev/null || true
        fi
    fi
    
    log_success "Environment setup completed"
}

# Deployment
deploy_service() {
    log_info "Deploying $SERVICE_NAME..."
    
    # Pull latest images
    log_info "Pulling latest images..."
    docker-compose pull
    
    # Start services
    log_info "Starting services..."
    docker-compose up -d
    
    # Wait for services to be ready
    log_info "Waiting for services to start..."
    sleep 10
    
    # Check service status
    if docker-compose ps | grep -q "Up"; then
        log_success "$SERVICE_NAME deployed successfully!"
        
        # Display access information
        echo
        log_info "Service Information:"
        docker-compose ps
        
        # Extract port from .env or use default
        PORT=$(grep "^[A-Z_]*PORT=" "$ENV_FILE" | head -1 | cut -d'=' -f2 || echo "[default-port]")
        
        echo
        log_info "Access your service at:"
        log_info "  Local: http://localhost:$PORT"
        log_info "  Network: http://$(hostname -I | awk '{print $1}'):$PORT"
        
    else
        log_error "Deployment failed. Check the logs:"
        docker-compose logs
        exit 1
    fi
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check container health
    CONTAINER_NAME=$(docker-compose ps -q)
    if [ -n "$CONTAINER_NAME" ]; then
        HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
        log_info "Container health status: $HEALTH_STATUS"
    fi
    
    # Check if service is responding (if health check endpoint is available)
    PORT=$(grep "^[A-Z_]*PORT=" "$ENV_FILE" | head -1 | cut -d'=' -f2 || echo "[default-port]")
    if command -v curl > /dev/null 2>&1; then
        if curl -f -s "http://localhost:$PORT" > /dev/null 2>&1; then
            log_success "Service is responding on port $PORT"
        else
            log_warning "Service may still be starting up on port $PORT"
        fi
    fi
    
    log_success "Deployment verification completed"
}

# Main execution
main() {
    echo "================================================"
    echo "  $SERVICE_NAME Deployment Script"
    echo "  Synology NAS Docker Management"
    echo "================================================"
    echo
    
    check_prerequisites
    setup_environment
    deploy_service
    verify_deployment
    
    echo
    log_success "Deployment completed successfully!"
    echo
    log_info "Next steps:"
    log_info "1. Access the web interface using the URLs above"
    log_info "2. Complete the initial setup if required"
    log_info "3. Configure backup using: ./backup.sh"
    log_info "4. Review the service documentation: README.md"
    echo
}

# Run main function
main "$@"
```

### backup.sh Template

```bash
#!/bin/bash
# [Service Name] Backup Script
# Automated backup for [Service Name] on Synology NAS

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="[service-name]"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
DATE=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default backup directory
DEFAULT_BACKUP_DIR="/volume1/docker/backups/$SERVICE_NAME"

# Functions
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

# Load environment variables
load_environment() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        BACKUP_DIR="${BACKUP_PATH:-$DEFAULT_BACKUP_DIR}"
    else
        log_warning ".env file not found, using default backup directory"
        BACKUP_DIR="$DEFAULT_BACKUP_DIR"
    fi
}

# Create backup directory
setup_backup_dir() {
    log_info "Setting up backup directory: $BACKUP_DIR"
    
    mkdir -p "$BACKUP_DIR"
    
    if [ ! -w "$BACKUP_DIR" ]; then
        log_error "Backup directory is not writable: $BACKUP_DIR"
        exit 1
    fi
    
    log_success "Backup directory ready"
}

# Stop service for consistent backup (optional)
stop_service() {
    if [ "$1" = "--stop-service" ]; then
        log_info "Stopping $SERVICE_NAME for consistent backup..."
        docker-compose stop
        RESTART_REQUIRED=true
    else
        log_info "Creating backup without stopping service (may be inconsistent)"
        RESTART_REQUIRED=false
    fi
}

# Create backup
create_backup() {
    log_info "Creating backup..."
    
    BACKUP_FILE="$BACKUP_DIR/${SERVICE_NAME}_backup_${DATE}.tar.gz"
    
    # Files and directories to backup
    BACKUP_ITEMS=""
    
    # Always backup configuration
    if [ -d "data" ]; then
        BACKUP_ITEMS="$BACKUP_ITEMS data"
    fi
    
    if [ -d "config" ]; then
        BACKUP_ITEMS="$BACKUP_ITEMS config"
    fi
    
    # Backup environment and compose files
    if [ -f "$ENV_FILE" ]; then
        BACKUP_ITEMS="$BACKUP_ITEMS $ENV_FILE"
    fi
    
    if [ -f "$COMPOSE_FILE" ]; then
        BACKUP_ITEMS="$BACKUP_ITEMS $COMPOSE_FILE"
    fi
    
    # Create the backup
    if [ -n "$BACKUP_ITEMS" ]; then
        log_info "Backing up: $BACKUP_ITEMS"
        tar -czf "$BACKUP_FILE" $BACKUP_ITEMS
        
        # Verify backup was created
        if [ -f "$BACKUP_FILE" ]; then
            BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            log_success "Backup created: $BACKUP_FILE ($BACKUP_SIZE)"
        else
            log_error "Failed to create backup file"
            exit 1
        fi
    else
        log_warning "No backup items found"
        exit 1
    fi
}

# Restart service if needed
restart_service() {
    if [ "$RESTART_REQUIRED" = true ]; then
        log_info "Restarting $SERVICE_NAME..."
        docker-compose start
        
        # Wait for service to be ready
        sleep 10
        
        if docker-compose ps | grep -q "Up"; then
            log_success "Service restarted successfully"
        else
            log_error "Failed to restart service"
            exit 1
        fi
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    local keep_days=${1:-7}  # Default: keep 7 days
    
    log_info "Cleaning up backups older than $keep_days days..."
    
    find "$BACKUP_DIR" -name "${SERVICE_NAME}_backup_*.tar.gz" -type f -mtime +$keep_days -delete 2>/dev/null || true
    
    local remaining_backups=$(ls -1 "$BACKUP_DIR"/${SERVICE_NAME}_backup_*.tar.gz 2>/dev/null | wc -l)
    log_info "Remaining backups: $remaining_backups"
}

# Verify backup integrity
verify_backup() {
    log_info "Verifying backup integrity..."
    
    if tar -tzf "$BACKUP_FILE" > /dev/null 2>&1; then
        log_success "Backup integrity verified"
    else
        log_error "Backup integrity check failed"
        exit 1
    fi
}

# Usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --stop-service    Stop service during backup for consistency"
    echo "  --keep-days N     Keep backups for N days (default: 7)"
    echo "  --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $0                           # Quick backup (service keeps running)"
    echo "  $0 --stop-service           # Consistent backup (stops service)"
    echo "  $0 --keep-days 30           # Keep backups for 30 days"
}

# Main execution
main() {
    local stop_service_flag=""
    local keep_days=7
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --stop-service)
                stop_service_flag="--stop-service"
                shift
                ;;
            --keep-days)
                keep_days="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "================================================"
    echo "  $SERVICE_NAME Backup Script"
    echo "  Synology NAS Docker Management"
    echo "================================================"
    echo
    
    cd "$SCRIPT_DIR"
    
    load_environment
    setup_backup_dir
    stop_service "$stop_service_flag"
    create_backup
    verify_backup
    restart_service
    cleanup_old_backups "$keep_days"
    
    echo
    log_success "Backup completed successfully!"
    echo
    log_info "Backup details:"
    log_info "  File: $BACKUP_FILE"
    log_info "  Size: $(du -h "$BACKUP_FILE" | cut -f1)"
    log_info "  Location: $BACKUP_DIR"
    echo
}

# Run main function
main "$@"
```

## Environment Configuration

### Variable Naming Conventions

Use consistent naming patterns for environment variables:

```env
# Service identification
SERVICE_NAME_PORT=9000
SERVICE_NAME_CONFIG_PATH=./config
SERVICE_NAME_DATA_PATH=./data

# Resource limits
SERVICE_NAME_MEMORY_LIMIT=512M
SERVICE_NAME_MEMORY_RESERVATION=256M

# Feature flags
SERVICE_NAME_FEATURE_ENABLED=true
SERVICE_NAME_DEBUG_MODE=false

# Security settings
SERVICE_NAME_ADMIN_USER=admin
SERVICE_NAME_API_KEY_FILE=/secrets/api.key
```

### Required Variables

Every service should include these standard variables:

```env
# System Configuration (Required)
PUID=1000
PGID=1000
TZ=UTC

# Network Configuration (Required)
[SERVICE_NAME]_PORT=[default-port]

# Storage Configuration (Required)
[SERVICE_NAME]_DATA_PATH=./data
[SERVICE_NAME]_CONFIG_PATH=./config

# Security Configuration (Required)
LOCAL_NETWORK_ONLY=true

# Resource Configuration (Required)
[SERVICE_NAME]_MEMORY_LIMIT=512M
[SERVICE_NAME]_MEMORY_RESERVATION=256M

# Backup Configuration (Required)
BACKUP_PATH=/volume1/docker/backups/[service-name]
```

## Documentation Standards

### README.md Structure

Every service README.md should follow this structure:

```markdown
# [Service Name] for Synology NAS

Brief description of the service and its purpose.

## Overview

Detailed description including:
- What the service does
- Key features
- Synology-specific optimizations

## Prerequisites

### System Requirements
- Hardware requirements
- Software requirements
- Network requirements

### Required Permissions
- User permissions needed
- File system access requirements

## Installation

### Method 1: Command Line Installation (Recommended)
Step-by-step CLI installation

### Method 2: Container Manager GUI Installation
GUI-based installation steps

## Configuration

### Environment Variables (.env file)
Description of all configuration options

### Advanced Configuration
Complex configuration scenarios

## First-Time Setup

Initial setup steps after deployment

## Post-Deployment Configuration

Additional configuration after initial setup

## Maintenance

Regular maintenance tasks and procedures

## Troubleshooting

Common issues and solutions

## Advanced Usage

Advanced features and integrations

## Migration and Backup

Backup and restore procedures

## Security Considerations

Security-specific guidance for this service

## Support

Links to documentation and support resources
```

### Documentation Requirements

1. **Comprehensive Coverage**: Document all features and configuration options
2. **Synology-Specific**: Include Synology NAS-specific instructions
3. **Security Focus**: Emphasize security considerations
4. **Troubleshooting**: Include common issues and solutions
5. **Examples**: Provide practical examples and use cases

## Deployment Scripts

### Script Requirements

1. **Error Handling**: Use `set -e` and proper error checking
2. **Logging**: Colored output for different message types
3. **Validation**: Check prerequisites before deployment
4. **User Guidance**: Provide clear instructions and next steps
5. **Idempotent**: Safe to run multiple times

### Script Standards

- Use consistent function naming and structure
- Include comprehensive error messages
- Provide usage information with `--help`
- Support common command-line options
- Log all important actions

## Backup Procedures

### Backup Requirements

1. **Data Integrity**: Stop service or ensure consistent state
2. **Comprehensive**: Include all configuration and data
3. **Automated**: Support automated scheduling
4. **Retention**: Configurable backup retention
5. **Verification**: Verify backup integrity

### Backup Standards

- Support both hot and cold backups
- Include verification steps
- Implement retention policies
- Provide restoration procedures
- Document backup/restore testing

## Testing and Validation

### Deployment Testing

```bash
# Test checklist for new services
1. Deploy service using deploy.sh
2. Verify service starts successfully
3. Test web interface access (if applicable)
4. Verify data persistence after restart
5. Test backup and restore procedures
6. Validate security configuration
7. Check resource usage
8. Verify integration with other services
```

### Validation Checklist

- [ ] Service follows directory structure
- [ ] All template files are properly customized
- [ ] Environment variables follow naming conventions
- [ ] Documentation is comprehensive and accurate
- [ ] Deploy script works correctly
- [ ] Backup script creates valid backups
- [ ] Security settings are properly configured
- [ ] Service integrates well with existing infrastructure

---

**Template Guide Version**: 1.0  
**Last Updated**: 2024  
**Compatibility**: Synology DSM 7.2+, Docker 20.10+

Use this template as a starting point for all new services. Customize as needed while maintaining consistency with the established patterns.