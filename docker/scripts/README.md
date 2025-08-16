# Docker Management Scripts

This directory contains utility scripts for automating Docker management tasks across the entire Synology NAS Docker infrastructure. These scripts provide bulk operations, maintenance automation, and monitoring capabilities to simplify day-to-day Docker administration.

## Script Categories

### System Management
- **System health monitoring and diagnostics**
- **Resource usage tracking and alerting**
- **Docker daemon management and maintenance**
- **Log management and rotation**

### Service Operations
- **Bulk service deployment and updates**
- **Service health checking and restart automation**
- **Configuration management across services**
- **Service dependency management**

### Backup and Recovery
- **Automated backup orchestration**
- **Backup verification and integrity checking**
- **Restoration procedures and testing**
- **Offsite backup synchronization**

### Maintenance and Cleanup
- **Docker resource cleanup (images, containers, volumes)**
- **Log file rotation and archival**
- **Performance optimization and tuning**
- **Security updates and patching**

## Planned Scripts

### Core Management Scripts

#### update-all.sh
Automated update system for all Docker services:
```bash
#!/bin/bash
# Update all Docker services across all categories
# Supports staged updates, rollback capabilities, and health verification

./update-all.sh [--dry-run] [--category=management] [--parallel]
```

#### backup-all.sh
Comprehensive backup solution for all services:
```bash
#!/bin/bash
# Create backups for all configured services
# Supports incremental backups, compression, and offsite sync

./backup-all.sh [--incremental] [--compress] [--offsite]
```

#### health-check.sh
System-wide health monitoring:
```bash
#!/bin/bash
# Monitor Docker daemon, containers, and system resources
# Generate alerts for issues and create health reports

./health-check.sh [--detailed] [--alerts] [--report]
```

#### cleanup.sh
Docker resource cleanup and optimization:
```bash
#!/bin/bash
# Clean up unused Docker resources
# Remove old images, stopped containers, and unused volumes

./cleanup.sh [--aggressive] [--preserve-days=7] [--dry-run]
```

### Service Management Scripts

#### deploy-category.sh
Deploy all services in a specific category:
```bash
#!/bin/bash
# Deploy all services in management, media, productivity, or networking

./deploy-category.sh management [--parallel] [--skip-existing]
```

#### restart-services.sh
Intelligent service restart with dependency handling:
```bash
#!/bin/bash
# Restart services with proper dependency order
# Handle inter-service dependencies and health checks

./restart-services.sh [--service=portainer] [--category=all] [--force]
```

#### check-updates.sh
Check for available updates across all services:
```bash
#!/bin/bash
# Scan for container image updates
# Generate update reports and recommendations

./check-updates.sh [--security-only] [--report-format=json]
```

### Monitoring and Diagnostics

#### monitor-resources.sh
Real-time resource monitoring:
```bash
#!/bin/bash
# Monitor CPU, memory, disk, and network usage
# Generate performance reports and alerts

./monitor-resources.sh [--continuous] [--threshold-cpu=80] [--alert-email]
```

#### collect-logs.sh
Centralized log collection and analysis:
```bash
#!/bin/bash
# Collect logs from all services
# Analyze for errors, warnings, and security events

./collect-logs.sh [--since=24h] [--level=error] [--export=archive]
```

#### diagnose-issues.sh
Automated issue diagnosis and resolution suggestions:
```bash
#!/bin/bash
# Diagnose common Docker and service issues
# Provide resolution recommendations

./diagnose-issues.sh [--service=portainer] [--auto-fix] [--report]
```

### Security and Maintenance

#### security-scan.sh
Comprehensive security scanning:
```bash
#!/bin/bash
# Scan containers for vulnerabilities
# Check configurations for security issues

./security-scan.sh [--full-scan] [--report-format=json] [--fix-critical]
```

#### rotate-logs.sh
Log rotation and archival:
```bash
#!/bin/bash
# Rotate and archive container logs
# Compress old logs and maintain retention policies

./rotate-logs.sh [--compress] [--retain-days=30] [--archive-path=/backups]
```

#### update-certificates.sh
SSL/TLS certificate management:
```bash
#!/bin/bash
# Update SSL certificates across services
# Validate certificate expiration and renewal

./update-certificates.sh [--check-expiry] [--auto-renew] [--notify]
```

## Script Standards

### Common Features

All scripts include these standard features:

```bash
#!/bin/bash
# Script header with description and usage

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"

# Command line argument parsing
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Description of what the script does"
    echo ""
    echo "Options:"
    echo "  --help          Show this help message"
    echo "  --dry-run       Show what would be done without executing"
    echo "  --verbose       Enable verbose output"
}

# Main execution
main() {
    # Script logic here
    log_info "Starting script execution..."
    
    # Implementation...
    
    log_success "Script completed successfully"
}

# Error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Parse arguments and run
case "${1:-}" in
    --help|-h)
        show_usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
```

### Configuration Management

Scripts use centralized configuration:

```bash
# Load global configuration
if [ -f "$PROJECT_ROOT/.env.global" ]; then
    source "$PROJECT_ROOT/.env.global"
fi

# Default configuration
BACKUP_PATH="${BACKUP_PATH:-/volume1/docker/backups}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
DRY_RUN="${DRY_RUN:-false}"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
```

### Service Discovery

Automatic service discovery for operations:

```bash
# Discover all services
discover_services() {
    local category="${1:-all}"
    local services=()
    
    if [ "$category" = "all" ]; then
        services=($(find "$COMPOSITIONS_DIR" -name "docker-compose.yml" -printf "%h\n"))
    else
        services=($(find "$COMPOSITIONS_DIR/$category" -name "docker-compose.yml" -printf "%h\n" 2>/dev/null || true))
    fi
    
    echo "${services[@]}"
}
```

### Parallel Execution

Safe parallel processing for bulk operations:

```bash
# Execute function on multiple services in parallel
parallel_execute() {
    local func="$1"
    local services=("${@:2}")
    local pids=()
    
    for service in "${services[@]}"; do
        if [ ${#pids[@]} -ge $PARALLEL_JOBS ]; then
            wait ${pids[0]}
            pids=("${pids[@]:1}")
        fi
        
        $func "$service" &
        pids+=($!)
    done
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait $pid
    done
}
```

## Usage Examples

### Daily Maintenance Routine

```bash
#!/bin/bash
# Daily maintenance script

# Health check
./health-check.sh --detailed

# Check for updates
./check-updates.sh --security-only

# Backup critical services
./backup-all.sh --incremental

# Clean up resources
./cleanup.sh --preserve-days=7

# Rotate logs
./rotate-logs.sh --compress
```

### Deployment Automation

```bash
#!/bin/bash
# Deploy complete infrastructure

# Deploy management tools first
./deploy-category.sh management --parallel

# Wait for management tools to be ready
sleep 30

# Deploy other categories
./deploy-category.sh media --parallel
./deploy-category.sh productivity --parallel
./deploy-category.sh networking --parallel

# Verify all deployments
./health-check.sh --detailed --alerts
```

### Update Workflow

```bash
#!/bin/bash
# Safe update workflow

# Check what updates are available
./check-updates.sh --report-format=json > updates.json

# Create backup before updates
./backup-all.sh --compress

# Perform updates with health checks
./update-all.sh --staged --verify-health

# Verify everything is working
./health-check.sh --detailed

# Clean up old images
./cleanup.sh --preserve-days=3
```

## Automation and Scheduling

### Cron Job Examples

```bash
# Add to crontab for automated maintenance

# Daily health check and cleanup
0 2 * * * /volume1/docker/syno-nas/docker/scripts/health-check.sh --report > /dev/null 2>&1

# Weekly full backup
0 3 * * 0 /volume1/docker/syno-nas/docker/scripts/backup-all.sh --compress --offsite

# Monthly security scan
0 4 1 * * /volume1/docker/syno-nas/docker/scripts/security-scan.sh --full-scan --report-format=json

# Daily log rotation
0 1 * * * /volume1/docker/syno-nas/docker/scripts/rotate-logs.sh --compress
```

### Systemd Services

For more advanced scheduling and service management:

```ini
# /etc/systemd/system/docker-health-check.service
[Unit]
Description=Docker Health Check Service
After=docker.service

[Service]
Type=oneshot
User=admin
ExecStart=/volume1/docker/syno-nas/docker/scripts/health-check.sh --detailed
```

```ini
# /etc/systemd/system/docker-health-check.timer
[Unit]
Description=Run Docker Health Check Daily
Requires=docker-health-check.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

## Integration with Services

### Service Metadata

Scripts can read service metadata for intelligent operations:

```bash
# Read service metadata from docker-compose.yml
get_service_metadata() {
    local service_dir="$1"
    local compose_file="$service_dir/docker-compose.yml"
    
    if [ -f "$compose_file" ]; then
        # Extract service name, category, and other metadata
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        echo "service=$service_name category=$category path=$service_dir"
    fi
}
```

### Health Check Integration

Scripts can leverage service health checks:

```bash
# Wait for service to be healthy
wait_for_health() {
    local service_dir="$1"
    local timeout="${2:-300}"  # 5 minutes default
    local elapsed=0
    
    cd "$service_dir"
    
    while [ $elapsed -lt $timeout ]; do
        if docker-compose ps | grep -q "healthy\|Up"; then
            return 0
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    return 1
}
```

## Error Handling and Recovery

### Robust Error Handling

```bash
# Error handling with cleanup
cleanup_on_error() {
    local exit_code=$?
    log_error "Script failed with exit code $exit_code"
    
    # Perform cleanup operations
    docker system prune -f >/dev/null 2>&1 || true
    
    exit $exit_code
}

trap cleanup_on_error ERR
```

### Recovery Procedures

```bash
# Service recovery function
recover_service() {
    local service_dir="$1"
    
    log_warning "Attempting to recover service: $(basename "$service_dir")"
    
    cd "$service_dir"
    
    # Stop service
    docker-compose down
    
    # Clean up
    docker system prune -f
    
    # Restart service
    docker-compose up -d
    
    # Verify health
    if wait_for_health "$service_dir" 60; then
        log_success "Service recovered successfully"
        return 0
    else
        log_error "Service recovery failed"
        return 1
    fi
}
```

## Logging and Monitoring

### Centralized Logging

```bash
# Logging configuration
LOG_FILE="/var/log/docker-scripts.log"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Enhanced logging function
log_with_timestamp() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}
```

### Monitoring Integration

```bash
# Send alerts for critical issues
send_alert() {
    local severity="$1"
    local message="$2"
    
    # Email alert (if configured)
    if [ -n "${ALERT_EMAIL:-}" ]; then
        echo "$message" | mail -s "Docker Alert: $severity" "$ALERT_EMAIL"
    fi
    
    # Slack/Discord webhook (if configured)
    if [ -n "${WEBHOOK_URL:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$severity: $message\"}" \
            "$WEBHOOK_URL"
    fi
}
```

## Security Considerations

### Secure Script Execution

```bash
# Verify script integrity
verify_script_integrity() {
    local script_path="$1"
    
    # Check file permissions
    if [ "$(stat -c '%a' "$script_path")" != "755" ]; then
        log_error "Script has incorrect permissions: $script_path"
        return 1
    fi
    
    # Check ownership
    if [ "$(stat -c '%U' "$script_path")" != "root" ]; then
        log_warning "Script not owned by root: $script_path"
    fi
}
```

### Sensitive Data Handling

```bash
# Secure environment handling
load_secure_config() {
    local config_file="$1"
    
    if [ -f "$config_file" ]; then
        # Check file permissions
        if [ "$(stat -c '%a' "$config_file")" -gt "600" ]; then
            log_error "Config file has insecure permissions: $config_file"
            return 1
        fi
        
        source "$config_file"
    fi
}
```

## Future Enhancements

### Planned Features

- **AI-Powered Diagnostics**: Machine learning for issue prediction
- **Advanced Monitoring**: Grafana integration for visualizations
- **Automated Scaling**: Dynamic resource allocation based on usage
- **Configuration Drift Detection**: Automated configuration compliance
- **Multi-NAS Orchestration**: Manage multiple Synology devices

### API Integration

- **REST API**: HTTP endpoints for script execution
- **WebSocket Events**: Real-time status updates
- **Webhook Support**: Integration with external systems
- **Mobile Notifications**: Push notifications for critical events

---

**Scripts Version**: 1.0  
**Last Updated**: 2024  
**Shell Compatibility**: Bash 4.0+  
**Requirements**: Docker 20.10+, Synology DSM 7.2+

These scripts provide the foundation for efficient Docker management on Synology NAS systems. As services are added to the infrastructure, corresponding automation will be implemented to maintain operational efficiency.