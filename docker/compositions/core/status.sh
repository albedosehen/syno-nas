#!/bin/bash
set -euo pipefail

# ===========================================
# UNIFIED CORE SERVICES STATUS SCRIPT
# ===========================================
# Health check and status monitoring for Synology NAS DS1520+
# Services: Portainer, SurrealDB, Doppler
# Platform: Linux/Synology DSM 7.2+
#
# Usage: ./status.sh [OPTIONS] [SERVICE]
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

# Status symbols
readonly CHECK_MARK="✅"
readonly CROSS_MARK="❌"
readonly WARNING_MARK="⚠️"
readonly INFO_MARK="ℹ️"
readonly GEAR_MARK="⚙️"

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly PROJECT_NAME="core-services"
readonly STATUS_LOG="${SCRIPT_DIR}/status.log"

# Global variables
VERBOSE=false
WATCH_MODE=false
WATCH_INTERVAL=5
JSON_OUTPUT=false
EXPORT_STATUS=false
SHOW_RESOURCES=false
SHOW_NETWORKS=false
SHOW_VOLUMES=false
DIAGNOSE_MODE=false
ALERT_MODE=false
SERVICE_FILTER=""
HEALTH_CHECK_TIMEOUT=30

# Available services
readonly SERVICES=("portainer" "surrealdb" "doppler" "all")

# Status codes
readonly STATUS_RUNNING=0
readonly STATUS_STOPPED=1
readonly STATUS_UNHEALTHY=2
readonly STATUS_MISSING=3
readonly STATUS_ERROR=4

# Logging functions
log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message"
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $message"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
}

log_debug() {
    local message="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $message"
    fi
}

# Help function
show_help() {
    cat << EOF
${CYAN}Unified Core Services Status Monitor${NC}

${YELLOW}USAGE:${NC}
    $0 [OPTIONS] [SERVICE]

${YELLOW}DESCRIPTION:${NC}
    Monitor health and status of unified core services.
    Provides comprehensive health checks, resource monitoring, and diagnostics.
    
    Optimized for Synology NAS DS1520+ with DSM 7.2+

${YELLOW}SERVICES:${NC}
    portainer               Check Portainer status only
    surrealdb               Check SurrealDB status only
    doppler                 Check Doppler status only
    all                     Check all services (default)

${YELLOW}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -w, --watch             Watch mode - continuously monitor status
    -i, --interval SECONDS  Watch interval (default: 5)
    -j, --json              Output status in JSON format
    -e, --export            Export status to file
    -r, --resources         Show resource usage (CPU, memory, disk)
    -n, --networks          Show network information
    -V, --volumes           Show volume information
    -d, --diagnose          Run comprehensive diagnostics
    -a, --alert             Alert mode - exit with error if any service unhealthy
    -t, --timeout SECONDS   Health check timeout (default: 30)
    
${YELLOW}EXAMPLES:${NC}
    $0                      # Show status of all services
    $0 portainer            # Check Portainer status only
    $0 -v                   # Verbose status with detailed information
    $0 -w                   # Watch mode - continuously monitor
    $0 -r                   # Show resource usage
    $0 -d                   # Run full diagnostics
    $0 -j                   # JSON output for scripting
    $0 -a                   # Alert mode for monitoring systems

${YELLOW}WATCH MODE:${NC}
    In watch mode, the status is refreshed every interval.
    Use Ctrl+C to exit watch mode.

${YELLOW}ALERT MODE:${NC}
    In alert mode, the script exits with:
    • 0: All services healthy
    • 1: Some services unhealthy
    • 2: Critical errors detected

${YELLOW}JSON OUTPUT:${NC}
    Provides machine-readable status information for integration
    with monitoring systems like Nagios, Zabbix, or Prometheus.

${YELLOW}DIAGNOSTICS:${NC}
    Comprehensive health checks including:
    • Container status and health
    • Network connectivity
    • Resource utilization
    • Port accessibility
    • Data integrity checks

For more information, see README.md
EOF
}

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get container status
get_container_status() {
    local container="$1"
    
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "missing"
        return $STATUS_MISSING
    fi
    
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        # Container is running, check health
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
        
        case "$health_status" in
            "healthy")
                echo "healthy"
                return $STATUS_RUNNING
                ;;
            "unhealthy")
                echo "unhealthy"
                return $STATUS_UNHEALTHY
                ;;
            "starting")
                echo "starting"
                return $STATUS_RUNNING
                ;;
            "no-healthcheck")
                echo "running"
                return $STATUS_RUNNING
                ;;
            *)
                echo "unknown"
                return $STATUS_ERROR
                ;;
        esac
    else
        echo "stopped"
        return $STATUS_STOPPED
    fi
}

# Get container uptime
get_container_uptime() {
    local container="$1"
    
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "N/A"
        return
    fi
    
    local started_at
    started_at=$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null || echo "")
    
    if [[ -n "$started_at" ]]; then
        local started_epoch
        started_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo "0")
        local current_epoch
        current_epoch=$(date +%s)
        local uptime_seconds=$((current_epoch - started_epoch))
        
        if [[ $uptime_seconds -lt 60 ]]; then
            echo "${uptime_seconds}s"
        elif [[ $uptime_seconds -lt 3600 ]]; then
            echo "$((uptime_seconds / 60))m"
        elif [[ $uptime_seconds -lt 86400 ]]; then
            echo "$((uptime_seconds / 3600))h $((uptime_seconds % 3600 / 60))m"
        else
            echo "$((uptime_seconds / 86400))d $((uptime_seconds % 86400 / 3600))h"
        fi
    else
        echo "N/A"
    fi
}

# Get container resource usage
get_container_resources() {
    local container="$1"
    
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "N/A,N/A,N/A"
        return
    fi
    
    # Use docker stats to get current resource usage
    local stats
    stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" "$container" 2>/dev/null || echo "N/A,N/A,N/A")
    echo "$stats"
}

# Test service connectivity
test_service_connectivity() {
    local service="$1"
    local container="core-${service}"
    
    case "$service" in
        "portainer")
            local port
            port=$(grep "PORTAINER_PORT" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "9000")
            if curl -f -s --max-time 10 "http://localhost:${port}/" >/dev/null 2>&1; then
                echo "accessible"
                return 0
            else
                echo "inaccessible"
                return 1
            fi
            ;;
        "surrealdb")
            local port
            port=$(grep "SURREALDB_PORT" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "8001")
            if curl -f -s --max-time 10 "http://localhost:${port}/health" >/dev/null 2>&1; then
                echo "accessible"
                return 0
            else
                echo "inaccessible"
                return 1
            fi
            ;;
        "doppler")
            # Doppler doesn't have direct connectivity test, check if container responds
            if docker exec "$container" doppler --version >/dev/null 2>&1; then
                echo "accessible"
                return 0
            else
                echo "inaccessible"
                return 1
            fi
            ;;
        *)
            echo "unknown"
            return 1
            ;;
    esac
}

# Get service detailed status
get_service_status() {
    local service="$1"
    local container="core-${service}"
    
    # Basic status
    local status
    local status_code
    status=$(get_container_status "$container")
    status_code=$?
    
    # Additional information
    local uptime
    uptime=$(get_container_uptime "$container")
    
    local resources
    resources=$(get_container_resources "$container")
    IFS=',' read -r cpu_percent mem_usage mem_percent <<< "$resources"
    
    local connectivity="N/A"
    if [[ $status_code -eq $STATUS_RUNNING ]]; then
        connectivity=$(test_service_connectivity "$service" 2>/dev/null || echo "unknown")
    fi
    
    # Port information
    local ports="N/A"
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        ports=$(docker port "$container" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo "N/A")
    fi
    
    # Return structured data
    echo "$status|$uptime|$cpu_percent|$mem_usage|$mem_percent|$connectivity|$ports"
}

# Display service status in table format
display_service_status() {
    local service="$1"
    local status_data="$2"
    
    IFS='|' read -r status uptime cpu_percent mem_usage mem_percent connectivity ports <<< "$status_data"
    
    # Status icon and color
    local status_icon=""
    local status_color=""
    
    case "$status" in
        "healthy"|"running")
            status_icon="$CHECK_MARK"
            status_color="$GREEN"
            ;;
        "starting")
            status_icon="$GEAR_MARK"
            status_color="$YELLOW"
            ;;
        "unhealthy")
            status_icon="$WARNING_MARK"
            status_color="$YELLOW"
            ;;
        "stopped")
            status_icon="$CROSS_MARK"
            status_color="$RED"
            ;;
        "missing")
            status_icon="$CROSS_MARK"
            status_color="$RED"
            ;;
        *)
            status_icon="$WARNING_MARK"
            status_color="$YELLOW"
            ;;
    esac
    
    # Display row
    printf "%-12s %s %-12s %-10s %-8s %-15s %-8s %-15s %s\n" \
        "$service" \
        "$status_icon" \
        "${status_color}${status}${NC}" \
        "$uptime" \
        "$cpu_percent" \
        "$mem_usage" \
        "$mem_percent" \
        "$connectivity" \
        "$ports"
}

# Display status in JSON format
display_json_status() {
    local services=("$@")
    
    echo "{"
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"services\": {"
    
    local first=true
    for service in "${services[@]}"; do
        if [[ "$first" == false ]]; then
            echo ","
        fi
        first=false
        
        local container="core-${service}"
        local status_data
        status_data=$(get_service_status "$service")
        
        IFS='|' read -r status uptime cpu_percent mem_usage mem_percent connectivity ports <<< "$status_data"
        
        echo "    \"$service\": {"
        echo "      \"status\": \"$status\","
        echo "      \"uptime\": \"$uptime\","
        echo "      \"cpu_percent\": \"$cpu_percent\","
        echo "      \"memory_usage\": \"$mem_usage\","
        echo "      \"memory_percent\": \"$mem_percent\","
        echo "      \"connectivity\": \"$connectivity\","
        echo "      \"ports\": \"$ports\""
        echo -n "    }"
    done
    
    echo
    echo "  }"
    echo "}"
}

# Show network information
show_network_info() {
    echo
    echo -e "${PURPLE}=== NETWORK INFORMATION ===${NC}"
    echo
    
    # Core network status
    if docker network ls --format "{{.Name}}" | grep -q "^core-network$"; then
        echo -e "${GREEN}$CHECK_MARK Core Network: active${NC}"
        
        if [[ "$VERBOSE" == true ]]; then
            echo
            echo "Network Details:"
            docker network inspect core-network --format "{{json .}}" | jq -r '
                "  Name: " + .Name,
                "  Driver: " + .Driver,
                "  Scope: " + .Scope,
                "  Subnet: " + (.IPAM.Config[0].Subnet // "N/A"),
                "  Gateway: " + (.IPAM.Config[0].Gateway // "N/A")
            ' 2>/dev/null || docker network inspect core-network | grep -E "(Name|Driver|Subnet|Gateway)"
        fi
    else
        echo -e "${RED}$CROSS_MARK Core Network: missing${NC}"
    fi
    
    # Container network connectivity
    echo
    echo "Inter-service connectivity:"
    local services=("portainer" "surrealdb" "doppler")
    
    for service in "${services[@]}"; do
        local container="core-${service}"
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            local connected_count=0
            for target_service in "${services[@]}"; do
                if [[ "$service" != "$target_service" ]]; then
                    local target_container="core-${target_service}"
                    if docker exec "$container" ping -c 1 "$target_container" >/dev/null 2>&1; then
                        ((connected_count++))
                    fi
                fi
            done
            
            if [[ $connected_count -eq $((${#services[@]} - 1)) ]]; then
                echo -e "  ${GREEN}$CHECK_MARK${NC} $service: can reach all services"
            else
                echo -e "  ${YELLOW}$WARNING_MARK${NC} $service: limited connectivity ($connected_count/2)"
            fi
        else
            echo -e "  ${RED}$CROSS_MARK${NC} $service: not running"
        fi
    done
}

# Show volume information
show_volume_info() {
    echo
    echo -e "${PURPLE}=== VOLUME INFORMATION ===${NC}"
    echo
    
    # Named volumes
    local volumes=("core_portainer_data" "core_surrealdb_data")
    for volume in "${volumes[@]}"; do
        if docker volume ls --format "{{.Name}}" | grep -q "^${volume}$"; then
            echo -e "${GREEN}$CHECK_MARK${NC} Volume: $volume"
            
            if [[ "$VERBOSE" == true ]]; then
                local mountpoint
                mountpoint=$(docker volume inspect "$volume" --format "{{.Mountpoint}}" 2>/dev/null || echo "N/A")
                echo "  Mountpoint: $mountpoint"
                
                if [[ "$mountpoint" != "N/A" ]] && [[ -d "$mountpoint" ]]; then
                    local size
                    size=$(du -sh "$mountpoint" 2>/dev/null | cut -f1 || echo "N/A")
                    echo "  Size: $size"
                fi
            fi
        else
            echo -e "${RED}$CROSS_MARK${NC} Volume: $volume (missing)"
        fi
    done
    
    # Bind mounts
    echo
    echo "Bind mount directories:"
    local data_dirs=(
        "/volume1/docker/core/portainer/data"
        "/volume1/docker/core/surrealdb/data"
        "/volume1/docker/core/doppler"
    )
    
    for dir in "${data_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size
            size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "N/A")
            local permissions
            permissions=$(ls -ld "$dir" | awk '{print $1}')
            echo -e "  ${GREEN}$CHECK_MARK${NC} $dir ($size, $permissions)"
        else
            echo -e "  ${RED}$CROSS_MARK${NC} $dir (missing)"
        fi
    done
}

# Show system resources
show_system_resources() {
    echo
    echo -e "${PURPLE}=== SYSTEM RESOURCES ===${NC}"
    echo
    
    # Memory usage
    local memory_info
    memory_info=$(free -h | awk 'NR==2{printf "Used: %s / %s (%.1f%%)", $3, $2, $3/$2*100}')
    echo -e "${INFO_MARK} Memory: $memory_info"
    
    # Disk usage
    local disk_info
    disk_info=$(df -h /volume1 2>/dev/null | awk 'NR==2{printf "Used: %s / %s (%s)", $3, $2, $5}' || echo "N/A")
    echo -e "${INFO_MARK} Disk (/volume1): $disk_info"
    
    # Docker system usage
    echo
    echo "Docker resource usage:"
    local docker_system_df
    docker_system_df=$(docker system df --format "table {{.Type}}\t{{.Total}}\t{{.Active}}\t{{.Size}}" 2>/dev/null || echo "N/A")
    if [[ "$docker_system_df" != "N/A" ]]; then
        echo "$docker_system_df"
    else
        echo "  Docker system info unavailable"
    fi
    
    # Load average
    local load_avg
    load_avg=$(uptime | grep -oE 'load average: [0-9.]+(, [0-9.]+)*' | cut -d':' -f2)
    echo
    echo -e "${INFO_MARK} Load average:$load_avg"
}

# Run comprehensive diagnostics
run_diagnostics() {
    echo
    echo -e "${PURPLE}=== COMPREHENSIVE DIAGNOSTICS ===${NC}"
    echo
    
    local issues_found=0
    
    # Check Docker daemon
    echo "Docker daemon status:"
    if docker info >/dev/null 2>&1; then
        echo -e "  ${GREEN}$CHECK_MARK${NC} Docker daemon is running"
    else
        echo -e "  ${RED}$CROSS_MARK${NC} Docker daemon is not accessible"
        ((issues_found++))
    fi
    
    # Check docker-compose file
    echo
    echo "Configuration checks:"
    if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
        echo -e "  ${GREEN}$CHECK_MARK${NC} docker-compose.yml exists"
        
        if docker-compose config >/dev/null 2>&1; then
            echo -e "  ${GREEN}$CHECK_MARK${NC} docker-compose.yml is valid"
        else
            echo -e "  ${RED}$CROSS_MARK${NC} docker-compose.yml has validation errors"
            ((issues_found++))
        fi
    else
        echo -e "  ${RED}$CROSS_MARK${NC} docker-compose.yml not found"
        ((issues_found++))
    fi
    
    # Check .env file
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        echo -e "  ${GREEN}$CHECK_MARK${NC} .env file exists"
        
        # Check required variables
        local required_vars=("DOPPLER_TOKEN" "PORTAINER_PORT" "SURREALDB_PORT")
        for var in "${required_vars[@]}"; do
            if grep -q "^${var}=" "${SCRIPT_DIR}/.env"; then
                echo -e "  ${GREEN}$CHECK_MARK${NC} Required variable $var is set"
            else
                echo -e "  ${RED}$CROSS_MARK${NC} Required variable $var is missing"
                ((issues_found++))
            fi
        done
    else
        echo -e "  ${RED}$CROSS_MARK${NC} .env file not found"
        ((issues_found++))
    fi
    
    # Check port availability
    echo
    echo "Port availability:"
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        source "${SCRIPT_DIR}/.env" 2>/dev/null || true
        
        local ports=("${PORTAINER_PORT:-9000}" "${SURREALDB_PORT:-8001}" "${PORTAINER_EDGE_PORT:-8000}")
        for port in "${ports[@]}"; do
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                echo -e "  ${YELLOW}$WARNING_MARK${NC} Port $port is in use"
            else
                echo -e "  ${GREEN}$CHECK_MARK${NC} Port $port is available"
            fi
        done
    fi
    
    # Check data directories
    echo
    echo "Data directory integrity:"
    local data_dirs=("/volume1/docker/core" "/volume1/docker/backups/core")
    for dir in "${data_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ -w "$dir" ]]; then
                echo -e "  ${GREEN}$CHECK_MARK${NC} $dir is writable"
            else
                echo -e "  ${RED}$CROSS_MARK${NC} $dir is not writable"
                ((issues_found++))
            fi
        else
            echo -e "  ${RED}$CROSS_MARK${NC} $dir does not exist"
            ((issues_found++))
        fi
    done
    
    # Summary
    echo
    if [[ $issues_found -eq 0 ]]; then
        echo -e "${GREEN}$CHECK_MARK Diagnostics completed: No issues found${NC}"
        return 0
    else
        echo -e "${RED}$CROSS_MARK Diagnostics completed: $issues_found issue(s) found${NC}"
        return 1
    fi
}

# Main status display
show_status() {
    local services_to_check=()
    
    if [[ -z "$SERVICE_FILTER" ]] || [[ "$SERVICE_FILTER" == "all" ]]; then
        services_to_check=("portainer" "surrealdb" "doppler")
    else
        services_to_check=("$SERVICE_FILTER")
    fi
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        display_json_status "${services_to_check[@]}"
        return
    fi
    
    # Header
    echo
    echo -e "${CYAN}Core Services Status - $(get_timestamp)${NC}"
    echo "=================================================================================="
    
    # Table header
    printf "%-12s %s %-12s %-10s %-8s %-15s %-8s %-15s %s\n" \
        "SERVICE" "ST" "STATUS" "UPTIME" "CPU" "MEMORY" "MEM%" "CONNECTIVITY" "PORTS"
    echo "=================================================================================="
    
    # Service status rows
    local overall_status=0
    for service in "${services_to_check[@]}"; do
        local status_data
        status_data=$(get_service_status "$service")
        display_service_status "$service" "$status_data"
        
        # Check for alert mode
        if [[ "$ALERT_MODE" == true ]]; then
            local status
            status=$(echo "$status_data" | cut -d'|' -f1)
            if [[ "$status" != "healthy" ]] && [[ "$status" != "running" ]]; then
                overall_status=1
            fi
        fi
    done
    
    echo "=================================================================================="
    
    # Additional information
    if [[ "$SHOW_RESOURCES" == true ]]; then
        show_system_resources
    fi
    
    if [[ "$SHOW_NETWORKS" == true ]]; then
        show_network_info
    fi
    
    if [[ "$SHOW_VOLUMES" == true ]]; then
        show_volume_info
    fi
    
    if [[ "$DIAGNOSE_MODE" == true ]]; then
        if ! run_diagnostics; then
            overall_status=2
        fi
    fi
    
    # Footer with summary
    echo
    local total_services=${#services_to_check[@]}
    local running_services=0
    
    for service in "${services_to_check[@]}"; do
        local container="core-${service}"
        local status
        status=$(get_container_status "$container")
        if [[ "$status" == "healthy" ]] || [[ "$status" == "running" ]]; then
            ((running_services++))
        fi
    done
    
    if [[ $running_services -eq $total_services ]]; then
        echo -e "${GREEN}$CHECK_MARK All services operational ($running_services/$total_services)${NC}"
    elif [[ $running_services -gt 0 ]]; then
        echo -e "${YELLOW}$WARNING_MARK Partial service availability ($running_services/$total_services)${NC}"
    else
        echo -e "${RED}$CROSS_MARK All services down ($running_services/$total_services)${NC}"
    fi
    
    if [[ "$ALERT_MODE" == true ]]; then
        exit $overall_status
    fi
}

# Watch mode
watch_status() {
    echo -e "${INFO_MARK} Entering watch mode (interval: ${WATCH_INTERVAL}s). Press Ctrl+C to exit."
    echo
    
    while true; do
        clear
        show_status
        sleep "$WATCH_INTERVAL"
    done
}

# Export status to file
export_status() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local export_file="./status_export_${timestamp}.json"
    
    log_info "Exporting status to: $export_file"
    
    # Export in JSON format regardless of current output mode
    local original_json_output=$JSON_OUTPUT
    JSON_OUTPUT=true
    
    show_status > "$export_file"
    
    # Add additional system information
    {
        echo
        echo "{"
        echo "  \"system_info\": {"
        echo "    \"hostname\": \"$(hostname)\","
        echo "    \"uptime\": \"$(uptime -p 2>/dev/null || uptime)\","
        echo "    \"docker_version\": \"$(docker --version 2>/dev/null || echo 'N/A')\","
        echo "    \"compose_version\": \"$(docker-compose --version 2>/dev/null || echo 'N/A')\""
        echo "  }"
        echo "}"
    } >> "$export_file"
    
    JSON_OUTPUT=$original_json_output
    
    log_info "Status exported successfully"
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
            -w|--watch)
                WATCH_MODE=true
                shift
                ;;
            -i|--interval)
                if [[ -n "$2" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    WATCH_INTERVAL="$2"
                    shift 2
                else
                    log_error "Invalid watch interval: $2"
                    exit 1
                fi
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -e|--export)
                EXPORT_STATUS=true
                shift
                ;;
            -r|--resources)
                SHOW_RESOURCES=true
                shift
                ;;
            -n|--networks)
                SHOW_NETWORKS=true
                shift
                ;;
            -V|--volumes)
                SHOW_VOLUMES=true
                shift
                ;;
            -d|--diagnose)
                DIAGNOSE_MODE=true
                shift
                ;;
            -a|--alert)
                ALERT_MODE=true
                shift
                ;;
            -t|--timeout)
                if [[ -n "$2" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    HEALTH_CHECK_TIMEOUT="$2"
                    shift 2
                else
                    log_error "Invalid timeout: $2"
                    exit 1
                fi
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                # This should be a service name
                if [[ -z "$SERVICE_FILTER" ]]; then
                    # Validate service name
                    local valid_service=false
                    for service in "${SERVICES[@]}"; do
                        if [[ "$1" == "$service" ]]; then
                            valid_service=true
                            break
                        fi
                    done
                    
                    if [[ "$valid_service" == true ]]; then
                        SERVICE_FILTER="$1"
                    else
                        log_error "Invalid service: $1"
                        log_info "Available services: ${SERVICES[*]}"
                        exit 1
                    fi
                else
                    log_error "Multiple services specified: $SERVICE_FILTER and $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# Main function
main() {
    log_debug "Starting core services status check..."
    log_debug "Options: VERBOSE=$VERBOSE, WATCH=$WATCH_MODE, JSON=$JSON_OUTPUT, ALERT=$ALERT_MODE"
    
    # Export mode
    if [[ "$EXPORT_STATUS" == true ]]; then
        export_status
        return 0
    fi
    
    # Watch mode
    if [[ "$WATCH_MODE" == true ]]; then
        watch_status
        return 0
    fi
    
    # Single status check
    show_status
}

# Handle Ctrl+C gracefully in watch mode
trap 'echo; log_info "Status monitoring stopped"; exit 0' SIGINT

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Initialize status log
    echo "=== Status Check Started at $(get_timestamp) ===" >> "$STATUS_LOG"
    
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi