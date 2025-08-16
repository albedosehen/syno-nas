#!/bin/bash

# Synology NAS Docker Management - System Health Check Script
# This script performs comprehensive health monitoring of Docker services,
# system resources, and infrastructure components

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"
HEALTH_CHECK_DATE=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Health status tracking
HEALTH_ISSUES=0
HEALTH_WARNINGS=0
HEALTH_CRITICAL=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    ((HEALTH_WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((HEALTH_ISSUES++))
}

log_critical() {
    echo -e "${RED}[CRITICAL]${NC} $1"
    ((HEALTH_CRITICAL++))
    ((HEALTH_ISSUES++))
}

log_step() {
    echo -e "${PURPLE}[CHECK]${NC} $1"
}

log_service() {
    echo -e "${CYAN}[SERVICE]${NC} $1"
}

# Help function
show_help() {
    echo "Synology NAS Docker Management - Health Check Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --category CATEGORY      Check only services in specified category"
    echo "                              (management, media, productivity, networking)"
    echo "  -s, --service SERVICE        Check only specified service"
    echo "  --detailed                  Perform detailed health checks"
    echo "  --system                    Check system resources only"
    echo "  --services                  Check services only"
    echo "  --docker                    Check Docker daemon only"
    echo "  --network                   Check network connectivity"
    echo "  --storage                   Check storage and disk usage"
    echo "  --alerts                    Generate alerts for critical issues"
    echo "  --report                    Generate detailed health report"
    echo "  --json                      Output results in JSON format"
    echo "  --continuous                Run continuous monitoring (use with caution)"
    echo "  --interval SECONDS          Monitoring interval for continuous mode (default: 300)"
    echo "  --threshold-cpu PERCENT     CPU usage warning threshold (default: 80)"
    echo "  --threshold-memory PERCENT  Memory usage warning threshold (default: 85)"
    echo "  --threshold-disk PERCENT    Disk usage warning threshold (default: 90)"
    echo "  --verbose                   Enable verbose output"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          Perform complete health check"
    echo "  $0 --detailed --alerts      Detailed check with alerting"
    echo "  $0 --system --threshold-cpu 70  Check system with custom CPU threshold"
    echo "  $0 -c management            Check only management services"
    echo "  $0 --continuous --interval 60    Continuous monitoring every minute"
    echo "  $0 --json > health-report.json  Generate JSON report"
    echo ""
}

# Parse command line arguments
TARGET_CATEGORY=""
TARGET_SERVICE=""
DETAILED_CHECK=false
SYSTEM_ONLY=false
SERVICES_ONLY=false
DOCKER_ONLY=false
NETWORK_CHECK=false
STORAGE_CHECK=false
GENERATE_ALERTS=false
GENERATE_REPORT=false
JSON_OUTPUT=false
CONTINUOUS_MODE=false
CHECK_INTERVAL=300
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--category)
            TARGET_CATEGORY="$2"
            shift 2
            ;;
        -s|--service)
            TARGET_SERVICE="$2"
            shift 2
            ;;
        --detailed)
            DETAILED_CHECK=true
            shift
            ;;
        --system)
            SYSTEM_ONLY=true
            shift
            ;;
        --services)
            SERVICES_ONLY=true
            shift
            ;;
        --docker)
            DOCKER_ONLY=true
            shift
            ;;
        --network)
            NETWORK_CHECK=true
            shift
            ;;
        --storage)
            STORAGE_CHECK=true
            shift
            ;;
        --alerts)
            GENERATE_ALERTS=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --continuous)
            CONTINUOUS_MODE=true
            shift
            ;;
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        --threshold-cpu)
            CPU_THRESHOLD="$2"
            shift 2
            ;;
        --threshold-memory)
            MEMORY_THRESHOLD="$2"
            shift 2
            ;;
        --threshold-disk)
            DISK_THRESHOLD="$2"
            shift 2
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

# Load global configuration
load_global_config() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
    
    # Set defaults from configuration
    HEALTH_MONITORING_ENABLED=${HEALTH_MONITORING_ENABLED:-true}
    HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-300}
    NOTIFICATIONS_ENABLED=${NOTIFICATIONS_ENABLED:-false}
    WEBHOOK_URL=${WEBHOOK_URL:-}
    NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL:-}
}

# Enhanced logging with verbose mode
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        log_info "VERBOSE: $1"
    fi
}

# JSON output functions
json_start() {
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"health_check\": {"
    fi
}

json_section() {
    if [ "$JSON_OUTPUT" = true ]; then
        echo "    \"$1\": {"
    fi
}

json_end_section() {
    if [ "$JSON_OUTPUT" = true ]; then
        echo "    },"
    fi
}

json_end() {
    if [ "$JSON_OUTPUT" = true ]; then
        echo "  },"
        echo "  \"summary\": {"
        echo "    \"total_issues\": $HEALTH_ISSUES,"
        echo "    \"warnings\": $HEALTH_WARNINGS,"
        echo "    \"critical\": $HEALTH_CRITICAL,"
        echo "    \"status\": \"$([ $HEALTH_CRITICAL -eq 0 ] && [ $HEALTH_ISSUES -eq 0 ] && echo "healthy" || echo "unhealthy")\""
        echo "  }"
        echo "}"
    fi
}

# Check Docker daemon health
check_docker_daemon() {
    if [ "$SERVICES_ONLY" = true ]; then
        return 0
    fi
    
    log_step "Checking Docker daemon health..."
    json_section "docker_daemon"
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_critical "Docker daemon is not running or not accessible"
        return 1
    fi
    
    log_success "Docker daemon is running"
    
    # Check Docker version
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    verbose_log "Docker version: $docker_version"
    
    # Check Docker storage driver
    local storage_driver=$(docker info --format '{{.Driver}}' 2>/dev/null)
    verbose_log "Storage driver: $storage_driver"
    
    # Check Docker root directory disk usage
    local docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
    if [ -n "$docker_root" ] && [ -d "$docker_root" ]; then
        local docker_usage=$(du -sh "$docker_root" 2>/dev/null | cut -f1)
        verbose_log "Docker root directory usage: $docker_usage"
    fi
    
    # Check for Docker system warnings
    local docker_warnings=$(docker info 2>&1 | grep -i "warning" || true)
    if [ -n "$docker_warnings" ]; then
        log_warning "Docker daemon warnings detected"
        verbose_log "Warnings: $docker_warnings"
    fi
    
    json_end_section
    log_success "Docker daemon health check completed"
}

# Check system resources
check_system_resources() {
    if [ "$SERVICES_ONLY" = true ] || [ "$DOCKER_ONLY" = true ]; then
        return 0
    fi
    
    log_step "Checking system resources..."
    json_section "system_resources"
    
    # CPU usage check
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d'%' -f1)
    if [ -z "$cpu_usage" ]; then
        # Alternative method for CPU usage
        cpu_usage=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}' | cut -d'.' -f1)
    fi
    
    if [ -n "$cpu_usage" ]; then
        if [ $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) -eq 1 ]; then
            log_warning "High CPU usage: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
        else
            log_success "CPU usage: ${cpu_usage}%"
        fi
        verbose_log "CPU usage: ${cpu_usage}%"
    else
        log_warning "Could not determine CPU usage"
    fi
    
    # Memory usage check
    local memory_info=$(free | grep Mem)
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local memory_usage_percent=$(echo "scale=1; $used_mem * 100 / $total_mem" | bc)
    
    if [ $(echo "$memory_usage_percent > $MEMORY_THRESHOLD" | bc -l) -eq 1 ]; then
        log_warning "High memory usage: ${memory_usage_percent}% (threshold: ${MEMORY_THRESHOLD}%)"
    else
        log_success "Memory usage: ${memory_usage_percent}%"
    fi
    
    verbose_log "Memory: $(echo $memory_info | awk '{printf "Used: %.1fGB / Total: %.1fGB", $3/1024/1024, $2/1024/1024}')"
    
    # Disk usage check
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ -n "$disk_usage" ]; then
        if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
            log_warning "High disk usage: ${disk_usage}% (threshold: ${DISK_THRESHOLD}%)"
        else
            log_success "Root disk usage: ${disk_usage}%"
        fi
    fi
    
    # Check Docker volume disk usage
    local docker_volumes_usage=$(df -h /volume1 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "")
    if [ -n "$docker_volumes_usage" ] && [ "$docker_volumes_usage" -gt "$DISK_THRESHOLD" ]; then
        log_warning "High Docker volume disk usage: ${docker_volumes_usage}%"
    elif [ -n "$docker_volumes_usage" ]; then
        log_success "Docker volume disk usage: ${docker_volumes_usage}%"
    fi
    
    # Load average check
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local load_threshold=$(echo "$cpu_cores * 0.7" | bc)
    
    if [ $(echo "$load_avg > $load_threshold" | bc -l) -eq 1 ]; then
        log_warning "High system load: $load_avg (cores: $cpu_cores)"
    else
        log_success "System load: $load_avg (cores: $cpu_cores)"
    fi
    
    json_end_section
    log_success "System resources check completed"
}

# Discover services
discover_services() {
    local category="${1:-all}"
    local service_name="${2:-}"
    local services=()
    
    if [ -n "$service_name" ]; then
        # Find specific service
        while IFS= read -r -d '' compose_file; do
            local service_dir=$(dirname "$compose_file")
            local current_service=$(basename "$service_dir")
            if [ "$current_service" = "$service_name" ]; then
                services+=("$service_dir")
                break
            fi
        done < <(find "$COMPOSITIONS_DIR" -name "docker-compose.yml" -print0 2>/dev/null)
    elif [ "$category" = "all" ]; then
        # Find all services
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

# Check individual service health
check_service_health() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_service "Checking $category/$service_name"
    
    cd "$service_dir"
    
    # Check if service is defined
    if [ ! -f "docker-compose.yml" ]; then
        log_error "$category/$service_name: No docker-compose.yml found"
        return 1
    fi
    
    # Get expected and running container counts
    local expected_containers=$(docker-compose config --services 2>/dev/null | wc -l)
    local running_containers=$(docker-compose ps --services --filter status=running 2>/dev/null | wc -l)
    local total_containers=$(docker-compose ps -q 2>/dev/null | wc -l)
    
    # Service status check
    if [ "$running_containers" -eq "$expected_containers" ] && [ "$expected_containers" -gt 0 ]; then
        log_success "$category/$service_name: All containers running ($running_containers/$expected_containers)"
    elif [ "$running_containers" -gt 0 ]; then
        log_warning "$category/$service_name: Partial service running ($running_containers/$expected_containers)"
    elif [ "$total_containers" -gt 0 ]; then
        log_error "$category/$service_name: Service stopped but containers exist"
    else
        log_error "$category/$service_name: Service not deployed"
    fi
    
    # Detailed health checks
    if [ "$DETAILED_CHECK" = true ]; then
        # Check container health status
        local unhealthy_containers=$(docker-compose ps | grep -c "unhealthy" || true)
        if [ "$unhealthy_containers" -gt 0 ]; then
            log_warning "$category/$service_name: $unhealthy_containers containers report unhealthy"
        fi
        
        # Check container restart counts
        local containers=$(docker-compose ps -q 2>/dev/null)
        for container in $containers; do
            if [ -n "$container" ]; then
                local restart_count=$(docker inspect --format='{{.RestartCount}}' "$container" 2>/dev/null || echo "0")
                if [ "$restart_count" -gt 5 ]; then
                    log_warning "$category/$service_name: Container $container has restarted $restart_count times"
                fi
            fi
        done
        
        # Check for recent errors in logs
        local error_count=$(docker-compose logs --since=1h 2>/dev/null | grep -i "error\|fatal\|exception" | wc -l || echo "0")
        if [ "$error_count" -gt 10 ]; then
            log_warning "$category/$service_name: $error_count errors found in recent logs"
        fi
    fi
    
    verbose_log "$category/$service_name: $running_containers/$expected_containers containers running"
}

# Check all services health
check_services_health() {
    if [ "$SYSTEM_ONLY" = true ] || [ "$DOCKER_ONLY" = true ]; then
        return 0
    fi
    
    log_step "Checking services health..."
    json_section "services"
    
    # Discover services to check
    local services=()
    
    if [ -n "$TARGET_SERVICE" ]; then
        services=($(discover_services "all" "$TARGET_SERVICE"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "Service '$TARGET_SERVICE' not found"
            return 1
        fi
    elif [ -n "$TARGET_CATEGORY" ]; then
        services=($(discover_services "$TARGET_CATEGORY"))
        if [ ${#services[@]} -eq 0 ]; then
            log_warning "No services found in category '$TARGET_CATEGORY'"
            return 0
        fi
    else
        # Check all services
        services=($(discover_services "all"))
        if [ ${#services[@]} -eq 0 ]; then
            log_warning "No services found"
            return 0
        fi
    fi
    
    log_info "Checking ${#services[@]} services..."
    
    for service_dir in "${services[@]}"; do
        check_service_health "$service_dir"
    done
    
    json_end_section
    log_success "Services health check completed"
}

# Check network connectivity
check_network_connectivity() {
    if [ "$NETWORK_CHECK" = false ] && [ "$DETAILED_CHECK" = false ]; then
        return 0
    fi
    
    log_step "Checking network connectivity..."
    json_section "network"
    
    # Check Docker networks
    local docker_networks=$(docker network ls --format "{{.Name}}" | grep -v "bridge\|host\|none" | head -5)
    
    for network in $docker_networks; do
        local network_containers=$(docker network inspect "$network" --format '{{len .Containers}}' 2>/dev/null || echo "0")
        verbose_log "Network $network: $network_containers containers connected"
    done
    
    # Test external connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_success "External network connectivity: OK"
    else
        log_warning "External network connectivity: Failed"
    fi
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        log_success "DNS resolution: OK"
    else
        log_warning "DNS resolution: Failed"
    fi
    
    json_end_section
    log_success "Network connectivity check completed"
}

# Check storage and volumes
check_storage() {
    if [ "$STORAGE_CHECK" = false ] && [ "$DETAILED_CHECK" = false ]; then
        return 0
    fi
    
    log_step "Checking storage and Docker volumes..."
    json_section "storage"
    
    # Check Docker volumes
    local volume_count=$(docker volume ls -q | wc -l)
    log_info "Docker volumes: $volume_count"
    
    # Check for dangling volumes
    local dangling_volumes=$(docker volume ls -f dangling=true -q | wc -l)
    if [ "$dangling_volumes" -gt 0 ]; then
        log_warning "Dangling Docker volumes: $dangling_volumes"
    else
        log_success "No dangling Docker volumes"
    fi
    
    # Check Docker system disk usage
    local docker_system_usage=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" 2>/dev/null | tail -n +2 | while read line; do echo "$line"; done)
    verbose_log "Docker system usage: $docker_system_usage"
    
    json_end_section
    log_success "Storage check completed"
}

# Generate alerts for critical issues
generate_alerts() {
    if [ "$GENERATE_ALERTS" = false ]; then
        return 0
    fi
    
    if [ "$HEALTH_CRITICAL" -gt 0 ] || [ "$HEALTH_ISSUES" -gt 5 ]; then
        local alert_message="ALERT: Docker Health Check Failure - Critical: $HEALTH_CRITICAL, Issues: $HEALTH_ISSUES, Warnings: $HEALTH_WARNINGS"
        
        log_step "Generating alerts..."
        
        # Email alert (if configured)
        if [ -n "$NOTIFICATION_EMAIL" ] && command -v mail >/dev/null 2>&1; then
            echo "$alert_message" | mail -s "Docker Health Alert - $(hostname)" "$NOTIFICATION_EMAIL"
            verbose_log "Email alert sent to $NOTIFICATION_EMAIL"
        fi
        
        # Webhook alert (if configured)
        if [ -n "$WEBHOOK_URL" ] && command -v curl >/dev/null 2>&1; then
            curl -X POST -H 'Content-type: application/json' \
                --data "{\"text\":\"$alert_message\"}" \
                "$WEBHOOK_URL" >/dev/null 2>&1
            verbose_log "Webhook alert sent to $WEBHOOK_URL"
        fi
        
        log_warning "Alerts generated for critical issues"
    fi
}

# Generate detailed health report
generate_health_report() {
    if [ "$GENERATE_REPORT" = false ] && [ "$JSON_OUTPUT" = false ]; then
        return 0
    fi
    
    local report_file="$PROJECT_ROOT/logs/health-report-$HEALTH_CHECK_DATE.txt"
    
    if [ "$GENERATE_REPORT" = true ]; then
        log_step "Generating detailed health report..."
        
        mkdir -p "$(dirname "$report_file")"
        
        cat > "$report_file" << EOF
Docker Management Health Report
===============================
Generated: $(date)
Host: $(hostname)

Summary:
- Total Issues: $HEALTH_ISSUES
- Warnings: $HEALTH_WARNINGS  
- Critical: $HEALTH_CRITICAL
- Overall Status: $([ $HEALTH_CRITICAL -eq 0 ] && [ $HEALTH_ISSUES -eq 0 ] && echo "HEALTHY" || echo "UNHEALTHY")

System Information:
- Uptime: $(uptime | cut -d',' -f1 | cut -d' ' -f4-)
- Load Average: $(uptime | awk -F'load average:' '{print $2}')
- Memory Usage: $(free -h | grep Mem | awk '{printf "%s / %s (%.1f%%)", $3, $2, $3/$2*100}')
- Disk Usage: $(df -h / | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')

Docker Information:
- Version: $(docker version --format '{{.Server.Version}}' 2>/dev/null)
- Running Containers: $(docker ps -q | wc -l)
- Total Images: $(docker images -q | wc -l)
- Networks: $(docker network ls | wc -l)
- Volumes: $(docker volume ls -q | wc -l)

EOF
        
        log_success "Health report generated: $report_file"
    fi
}

# Display health summary
show_health_summary() {
    echo ""
    echo "========================================"
    echo "         Health Check Summary"
    echo "========================================"
    echo ""
    
    echo "Health Status:"
    if [ "$HEALTH_CRITICAL" -eq 0 ] && [ "$HEALTH_ISSUES" -eq 0 ]; then
        log_success "Overall Status: HEALTHY"
    elif [ "$HEALTH_CRITICAL" -eq 0 ]; then
        log_warning "Overall Status: WARNING"
    else
        log_critical "Overall Status: CRITICAL"
    fi
    
    echo ""
    echo "Issue Summary:"
    echo "  Critical Issues: $HEALTH_CRITICAL"
    echo "  Total Issues: $HEALTH_ISSUES"
    echo "  Warnings: $HEALTH_WARNINGS"
    echo ""
    
    if [ "$HEALTH_ISSUES" -gt 0 ] || [ "$HEALTH_WARNINGS" -gt 0 ]; then
        echo "Recommendations:"
        echo "  - Review service logs for detailed error information"
        echo "  - Check system resources and available disk space"
        echo "  - Restart failed services if necessary"
        echo "  - Consider scaling down services if resource constrained"
        echo ""
    fi
    
    echo "Next Steps:"
    echo "  - Monitor logs: docker/scripts/manage-services.sh logs"
    echo "  - Check service status: docker/scripts/manage-services.sh status"
    echo "  - System cleanup: docker/scripts/cleanup.sh"
    echo ""
}

# Main health check execution
perform_health_check() {
    if [ "$JSON_OUTPUT" = true ]; then
        json_start
    fi
    
    check_docker_daemon
    check_system_resources
    check_services_health
    check_network_connectivity
    check_storage
    
    if [ "$JSON_OUTPUT" = true ]; then
        json_end
    else
        show_health_summary
        generate_health_report
        generate_alerts
    fi
}

# Continuous monitoring mode
continuous_monitoring() {
    log_info "Starting continuous monitoring mode (interval: ${CHECK_INTERVAL}s)"
    log_warning "Press Ctrl+C to stop monitoring"
    
    while true; do
        echo ""
        echo "========================================"
        echo "Health Check - $(date)"
        echo "========================================"
        
        # Reset counters for each iteration
        HEALTH_ISSUES=0
        HEALTH_WARNINGS=0
        HEALTH_CRITICAL=0
        
        perform_health_check
        
        if [ "$JSON_OUTPUT" = false ]; then
            log_info "Next check in ${CHECK_INTERVAL} seconds..."
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Main execution
main() {
    if [ "$CONTINUOUS_MODE" = false ] && [ "$JSON_OUTPUT" = false ]; then
        echo "========================================"
        echo "     Docker Health Check Script"
        echo "========================================"
        echo ""
    fi
    
    cd "$PROJECT_ROOT"
    load_global_config
    
    # Check if health monitoring is enabled
    if [ "$HEALTH_MONITORING_ENABLED" = false ] && [ "$CONTINUOUS_MODE" = false ]; then
        log_warning "Health monitoring is disabled in configuration"
    fi
    
    if [ "$CONTINUOUS_MODE" = true ]; then
        continuous_monitoring
    else
        perform_health_check
        
        if [ "$JSON_OUTPUT" = false ]; then
            if [ "$HEALTH_CRITICAL" -eq 0 ] && [ "$HEALTH_ISSUES" -eq 0 ]; then
                log_success "Health check completed - System is healthy!"
            else
                log_error "Health check completed - Issues detected!"
                exit 1
            fi
        fi
    fi
}

# Error handling
trap 'log_error "Health check script failed on line $LINENO"' ERR

# Handle Ctrl+C for continuous mode
trap 'echo ""; log_info "Monitoring stopped by user"; exit 0' INT

# Execute main function
main "$@"