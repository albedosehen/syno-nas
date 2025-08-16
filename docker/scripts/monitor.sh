#!/bin/bash

# Synology NAS Docker Management - Continuous Monitoring Script
# This script provides real-time monitoring of Docker services, system resources,
# and automated alerting for critical issues

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"
MONITOR_PID_FILE="/tmp/syno-nas-monitor.pid"
MONITOR_LOG_FILE="$PROJECT_ROOT/logs/monitor.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Monitoring state
MONITORING_ACTIVE=false
ALERT_COOLDOWN=()

# Logging functions
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$timestamp] [INFO] $1" >> "$MONITOR_LOG_FILE"
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[OK]${NC} $1"
    echo "[$timestamp] [OK] $1" >> "$MONITOR_LOG_FILE"
}

log_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$timestamp] [WARNING] $1" >> "$MONITOR_LOG_FILE"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$timestamp] [ERROR] $1" >> "$MONITOR_LOG_FILE"
}

log_alert() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ALERT]${NC} $1"
    echo "[$timestamp] [ALERT] $1" >> "$MONITOR_LOG_FILE"
}

log_monitor() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}[MONITOR]${NC} $1"
    echo "[$timestamp] [MONITOR] $1" >> "$MONITOR_LOG_FILE"
}

# Help function
show_help() {
    echo "Synology NAS Docker Management - Continuous Monitoring Script"
    echo ""
    echo "Usage: $0 [action] [options]"
    echo ""
    echo "Actions:"
    echo "  start                       Start continuous monitoring"
    echo "  stop                        Stop continuous monitoring"
    echo "  status                      Show monitoring status"
    echo "  restart                     Restart monitoring"
    echo "  logs                        Show monitoring logs"
    echo ""
    echo "Options:"
    echo "  --interval SECONDS          Monitoring interval (default: 300)"
    echo "  --threshold-cpu PERCENT     CPU usage alert threshold (default: 85)"
    echo "  --threshold-memory PERCENT  Memory usage alert threshold (default: 90)"
    echo "  --threshold-disk PERCENT    Disk usage alert threshold (default: 95)"
    echo "  --alert-cooldown SECONDS    Minimum time between alerts (default: 3600)"
    echo "  --enable-recovery           Enable automatic service recovery"
    echo "  --recovery-attempts COUNT   Max recovery attempts per service (default: 3)"
    echo "  --log-level LEVEL          Log level: DEBUG, INFO, WARN, ERROR (default: INFO)"
    echo "  --dashboard                 Show real-time dashboard"
    echo "  --json                      Output monitoring data in JSON format"
    echo "  --webhook-alerts            Enable webhook notifications"
    echo "  --email-alerts              Enable email notifications"
    echo "  --foreground                Run in foreground (don't daemonize)"
    echo "  --verbose                   Enable verbose output"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start                    Start monitoring with default settings"
    echo "  $0 start --interval 60      Start monitoring with 1-minute intervals"
    echo "  $0 start --dashboard        Start monitoring with real-time dashboard"
    echo "  $0 status                   Check if monitoring is running"
    echo "  $0 logs                     View monitoring logs"
    echo "  $0 stop                     Stop monitoring"
    echo ""
}

# Parse command line arguments
ACTION=""
MONITOR_INTERVAL=300
CPU_THRESHOLD=85
MEMORY_THRESHOLD=90
DISK_THRESHOLD=95
ALERT_COOLDOWN_TIME=3600
ENABLE_RECOVERY=false
RECOVERY_ATTEMPTS=3
LOG_LEVEL="INFO"
SHOW_DASHBOARD=false
JSON_OUTPUT=false
WEBHOOK_ALERTS=false
EMAIL_ALERTS=false
FOREGROUND_MODE=false
VERBOSE=false

# Parse action (required first argument)
if [ $# -eq 0 ]; then
    log_error "Action is required"
    show_help
    exit 1
fi

ACTION="$1"
shift

# Validate action
case "$ACTION" in
    start|stop|status|restart|logs)
        ;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    *)
        log_error "Unknown action: $ACTION"
        show_help
        exit 1
        ;;
esac

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --interval)
            MONITOR_INTERVAL="$2"
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
        --alert-cooldown)
            ALERT_COOLDOWN_TIME="$2"
            shift 2
            ;;
        --enable-recovery)
            ENABLE_RECOVERY=true
            shift
            ;;
        --recovery-attempts)
            RECOVERY_ATTEMPTS="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --dashboard)
            SHOW_DASHBOARD=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --webhook-alerts)
            WEBHOOK_ALERTS=true
            shift
            ;;
        --email-alerts)
            EMAIL_ALERTS=true
            shift
            ;;
        --foreground)
            FOREGROUND_MODE=true
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
    
    # Override with command line options
    if [ "$WEBHOOK_ALERTS" = true ] && [ -n "$WEBHOOK_URL" ]; then
        NOTIFICATIONS_ENABLED=true
    fi
    
    if [ "$EMAIL_ALERTS" = true ] && [ -n "$NOTIFICATION_EMAIL" ]; then
        NOTIFICATIONS_ENABLED=true
    fi
}

# Enhanced logging with verbose mode
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        log_info "VERBOSE: $1"
    fi
}

# Check if monitoring is already running
is_monitoring_running() {
    if [ -f "$MONITOR_PID_FILE" ]; then
        local pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0  # Running
        else
            # PID file exists but process is dead
            rm -f "$MONITOR_PID_FILE"
            return 1  # Not running
        fi
    fi
    return 1  # Not running
}

# Setup monitoring environment
setup_monitoring() {
    # Create log directory
    mkdir -p "$(dirname "$MONITOR_LOG_FILE")"
    
    # Initialize log file
    touch "$MONITOR_LOG_FILE"
    
    # Set up signal handlers for graceful shutdown
    trap 'cleanup_monitoring; exit 0' SIGTERM SIGINT
}

# Cleanup monitoring resources
cleanup_monitoring() {
    log_monitor "Stopping monitoring..."
    MONITORING_ACTIVE=false
    
    if [ -f "$MONITOR_PID_FILE" ]; then
        rm -f "$MONITOR_PID_FILE"
    fi
    
    log_monitor "Monitoring stopped"
}

# Check if alert cooldown is active
is_alert_on_cooldown() {
    local alert_type="$1"
    local current_time=$(date +%s)
    
    for entry in "${ALERT_COOLDOWN[@]}"; do
        local type=$(echo "$entry" | cut -d: -f1)
        local timestamp=$(echo "$entry" | cut -d: -f2)
        
        if [ "$type" = "$alert_type" ]; then
            local time_diff=$((current_time - timestamp))
            if [ $time_diff -lt $ALERT_COOLDOWN_TIME ]; then
                return 0  # On cooldown
            fi
        fi
    done
    
    return 1  # Not on cooldown
}

# Add alert to cooldown
add_alert_cooldown() {
    local alert_type="$1"
    local current_time=$(date +%s)
    
    # Remove existing entry for this alert type
    local new_cooldown=()
    for entry in "${ALERT_COOLDOWN[@]}"; do
        local type=$(echo "$entry" | cut -d: -f1)
        if [ "$type" != "$alert_type" ]; then
            new_cooldown+=("$entry")
        fi
    done
    
    # Add new entry
    new_cooldown+=("$alert_type:$current_time")
    ALERT_COOLDOWN=("${new_cooldown[@]}")
}

# Send alert notification
send_alert() {
    local alert_type="$1"
    local message="$2"
    
    if is_alert_on_cooldown "$alert_type"; then
        verbose_log "Alert $alert_type is on cooldown, skipping notification"
        return 0
    fi
    
    log_alert "$message"
    
    if [ "$NOTIFICATIONS_ENABLED" = true ]; then
        # Email alert
        if [ "$EMAIL_ALERTS" = true ] && [ -n "$NOTIFICATION_EMAIL" ] && command -v mail >/dev/null 2>&1; then
            echo "$message" | mail -s "Docker Monitor Alert - $(hostname)" "$NOTIFICATION_EMAIL"
            verbose_log "Email alert sent to $NOTIFICATION_EMAIL"
        fi
        
        # Webhook alert
        if [ "$WEBHOOK_ALERTS" = true ] && [ -n "$WEBHOOK_URL" ] && command -v curl >/dev/null 2>&1; then
            curl -X POST -H 'Content-type: application/json' \
                --data "{\"text\":\"$message\"}" \
                "$WEBHOOK_URL" >/dev/null 2>&1
            verbose_log "Webhook alert sent to $WEBHOOK_URL"
        fi
        
        # Add to cooldown
        add_alert_cooldown "$alert_type"
    fi
}

# Monitor system resources
monitor_system_resources() {
    verbose_log "Checking system resources"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d'%' -f1 2>/dev/null || echo "0")
    if [ -z "$cpu_usage" ]; then
        cpu_usage=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print int(usage)}' 2>/dev/null || echo "0")
    fi
    
    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        send_alert "high_cpu" "High CPU usage detected: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
    fi
    
    # Memory usage
    local memory_info=$(free | grep Mem)
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local memory_usage_percent=$(echo "scale=0; $used_mem * 100 / $total_mem" | bc 2>/dev/null || echo "0")
    
    if [ "$memory_usage_percent" -gt "$MEMORY_THRESHOLD" ]; then
        send_alert "high_memory" "High memory usage detected: ${memory_usage_percent}% (threshold: ${MEMORY_THRESHOLD}%)"
    fi
    
    # Disk usage
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    
    if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
        send_alert "high_disk" "High disk usage detected: ${disk_usage}% (threshold: ${DISK_THRESHOLD}%)"
    fi
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{\"cpu_usage\":$cpu_usage,\"memory_usage\":$memory_usage_percent,\"disk_usage\":$disk_usage,\"timestamp\":\"$(date -Iseconds)\"}"
    fi
}

# Monitor Docker daemon
monitor_docker_daemon() {
    verbose_log "Checking Docker daemon"
    
    if ! docker info >/dev/null 2>&1; then
        send_alert "docker_daemon" "Docker daemon is not running or not accessible"
        return 1
    fi
    
    # Check for Docker daemon warnings
    local docker_warnings=$(docker info 2>&1 | grep -i "warning" | wc -l)
    if [ "$docker_warnings" -gt 0 ]; then
        log_warning "Docker daemon has $docker_warnings warnings"
    fi
    
    return 0
}

# Discover services to monitor
discover_services() {
    local services=()
    
    while IFS= read -r -d '' compose_file; do
        local service_dir=$(dirname "$compose_file")
        services+=("$service_dir")
    done < <(find "$COMPOSITIONS_DIR" -name "docker-compose.yml" -print0 2>/dev/null)
    
    echo "${services[@]}"
}

# Monitor individual service
monitor_service() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    verbose_log "Checking service $category/$service_name"
    
    cd "$service_dir"
    
    # Check if service is defined
    if [ ! -f "docker-compose.yml" ]; then
        log_error "$category/$service_name: No docker-compose.yml found"
        return 1
    fi
    
    # Get container status
    local expected_containers=$(docker-compose config --services 2>/dev/null | wc -l)
    local running_containers=$(docker-compose ps --services --filter status=running 2>/dev/null | wc -l)
    
    # Service health check
    if [ "$running_containers" -lt "$expected_containers" ]; then
        local alert_message="Service $category/$service_name has $running_containers/$expected_containers containers running"
        
        if [ "$ENABLE_RECOVERY" = true ]; then
            log_warning "$alert_message - Attempting recovery"
            
            # Attempt service recovery
            if attempt_service_recovery "$service_dir"; then
                log_success "Successfully recovered $category/$service_name"
            else
                send_alert "service_failure" "Failed to recover $category/$service_name after $RECOVERY_ATTEMPTS attempts"
            fi
        else
            send_alert "service_failure" "$alert_message"
        fi
        
        return 1
    fi
    
    # Check for unhealthy containers
    local unhealthy_containers=$(docker-compose ps | grep -c "unhealthy" 2>/dev/null || echo "0")
    if [ "$unhealthy_containers" -gt 0 ]; then
        send_alert "service_unhealthy" "$category/$service_name has $unhealthy_containers unhealthy containers"
    fi
    
    return 0
}

# Attempt service recovery
attempt_service_recovery() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    cd "$service_dir"
    
    local attempts=0
    while [ $attempts -lt $RECOVERY_ATTEMPTS ]; do
        ((attempts++))
        log_info "Recovery attempt $attempts/$RECOVERY_ATTEMPTS for $category/$service_name"
        
        # Try to restart the service
        if docker-compose restart; then
            sleep 10  # Give service time to start
            
            # Check if recovery was successful
            local running_containers=$(docker-compose ps --services --filter status=running 2>/dev/null | wc -l)
            local expected_containers=$(docker-compose config --services 2>/dev/null | wc -l)
            
            if [ "$running_containers" -eq "$expected_containers" ]; then
                return 0  # Recovery successful
            fi
        fi
        
        sleep 5  # Wait before next attempt
    done
    
    return 1  # Recovery failed
}

# Monitor all services
monitor_services() {
    verbose_log "Checking all services"
    
    local services=($(discover_services))
    local failed_services=0
    
    for service_dir in "${services[@]}"; do
        if ! monitor_service "$service_dir"; then
            ((failed_services++))
        fi
    done
    
    if [ "$failed_services" -gt 0 ]; then
        log_warning "$failed_services services have issues"
    fi
}

# Display real-time dashboard
show_dashboard() {
    clear
    echo "========================================"
    echo "    Docker Management Monitor"
    echo "========================================"
    echo "Last Update: $(date)"
    echo ""
    
    # System resources
    echo "System Resources:"
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d'%' -f1 2>/dev/null || echo "0")
    local memory_info=$(free | grep Mem)
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local memory_usage_percent=$(echo "scale=1; $used_mem * 100 / $total_mem" | bc 2>/dev/null || echo "0")
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    
    printf "  CPU: %s%% " "$cpu_usage"
    [ "$cpu_usage" -gt "$CPU_THRESHOLD" ] && printf "${RED}[HIGH]${NC}" || printf "${GREEN}[OK]${NC}"
    echo ""
    
    printf "  Memory: %s%% " "$memory_usage_percent"
    [ "${memory_usage_percent%.*}" -gt "$MEMORY_THRESHOLD" ] && printf "${RED}[HIGH]${NC}" || printf "${GREEN}[OK]${NC}"
    echo ""
    
    printf "  Disk: %s%% " "$disk_usage"
    [ "$disk_usage" -gt "$DISK_THRESHOLD" ] && printf "${RED}[HIGH]${NC}" || printf "${GREEN}[OK]${NC}"
    echo ""
    
    echo ""
    echo "Docker Services:"
    
    # Service status
    local services=($(discover_services))
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        cd "$service_dir"
        
        local expected_containers=$(docker-compose config --services 2>/dev/null | wc -l)
        local running_containers=$(docker-compose ps --services --filter status=running 2>/dev/null | wc -l)
        
        printf "  %s/%s: %d/%d " "$category" "$service_name" "$running_containers" "$expected_containers"
        
        if [ "$running_containers" -eq "$expected_containers" ]; then
            printf "${GREEN}[RUNNING]${NC}"
        elif [ "$running_containers" -gt 0 ]; then
            printf "${YELLOW}[PARTIAL]${NC}"
        else
            printf "${RED}[STOPPED]${NC}"
        fi
        echo ""
    done
    
    echo ""
    echo "Press Ctrl+C to stop monitoring"
}

# Main monitoring loop
monitoring_loop() {
    log_monitor "Starting monitoring loop (interval: ${MONITOR_INTERVAL}s)"
    MONITORING_ACTIVE=true
    
    while [ "$MONITORING_ACTIVE" = true ]; do
        if [ "$SHOW_DASHBOARD" = true ]; then
            show_dashboard
        fi
        
        # Perform monitoring checks
        monitor_docker_daemon
        monitor_system_resources
        monitor_services
        
        # Wait for next interval
        sleep "$MONITOR_INTERVAL"
    done
}

# Start monitoring
start_monitoring() {
    if is_monitoring_running; then
        log_error "Monitoring is already running (PID: $(cat "$MONITOR_PID_FILE"))"
        exit 1
    fi
    
    log_monitor "Starting Docker monitoring..."
    setup_monitoring
    
    if [ "$FOREGROUND_MODE" = true ] || [ "$SHOW_DASHBOARD" = true ]; then
        # Run in foreground
        echo $$ > "$MONITOR_PID_FILE"
        monitoring_loop
    else
        # Run in background
        nohup bash -c "
            echo \$\$ > '$MONITOR_PID_FILE'
            cd '$PROJECT_ROOT'
            source '$ENV_FILE' 2>/dev/null || true
            export MONITORING_ACTIVE=true
            export ALERT_COOLDOWN=()
            $(declare -f load_global_config monitor_docker_daemon monitor_system_resources discover_services monitor_service attempt_service_recovery monitor_services is_alert_on_cooldown add_alert_cooldown send_alert verbose_log log_info log_success log_warning log_error log_alert log_monitor)
            load_global_config
            while [ \"\$MONITORING_ACTIVE\" = true ]; do
                monitor_docker_daemon
                monitor_system_resources  
                monitor_services
                sleep '$MONITOR_INTERVAL'
            done
        " > /dev/null 2>&1 &
        
        sleep 2  # Give time for background process to start
        
        if is_monitoring_running; then
            log_success "Monitoring started (PID: $(cat "$MONITOR_PID_FILE"))"
        else
            log_error "Failed to start monitoring"
            exit 1
        fi
    fi
}

# Stop monitoring
stop_monitoring() {
    if ! is_monitoring_running; then
        log_warning "Monitoring is not running"
        exit 0
    fi
    
    local pid=$(cat "$MONITOR_PID_FILE")
    log_monitor "Stopping monitoring (PID: $pid)..."
    
    if kill "$pid" 2>/dev/null; then
        # Wait for process to stop
        local attempts=0
        while [ $attempts -lt 10 ]; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 1
            ((attempts++))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
        fi
        
        rm -f "$MONITOR_PID_FILE"
        log_success "Monitoring stopped"
    else
        log_error "Failed to stop monitoring process"
        rm -f "$MONITOR_PID_FILE"  # Clean up stale PID file
        exit 1
    fi
}

# Show monitoring status
show_status() {
    if is_monitoring_running; then
        local pid=$(cat "$MONITOR_PID_FILE")
        local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' ')
        
        echo "Monitoring Status: RUNNING"
        echo "PID: $pid"
        echo "Started: $start_time"
        echo "Log File: $MONITOR_LOG_FILE"
        echo ""
        echo "Configuration:"
        echo "  Interval: ${MONITOR_INTERVAL}s"
        echo "  CPU Threshold: ${CPU_THRESHOLD}%"
        echo "  Memory Threshold: ${MEMORY_THRESHOLD}%"
        echo "  Disk Threshold: ${DISK_THRESHOLD}%"
        echo "  Recovery Enabled: $ENABLE_RECOVERY"
        echo "  Notifications: $NOTIFICATIONS_ENABLED"
    else
        echo "Monitoring Status: STOPPED"
    fi
}

# Show monitoring logs
show_logs() {
    if [ ! -f "$MONITOR_LOG_FILE" ]; then
        log_warning "No monitoring log file found"
        exit 0
    fi
    
    echo "Monitoring Logs:"
    echo "================"
    tail -n 50 "$MONITOR_LOG_FILE"
}

# Restart monitoring
restart_monitoring() {
    log_monitor "Restarting monitoring..."
    
    if is_monitoring_running; then
        stop_monitoring
        sleep 2
    fi
    
    start_monitoring
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    load_global_config
    
    case "$ACTION" in
        start)
            start_monitoring
            ;;
        stop)
            stop_monitoring
            ;;
        status)
            show_status
            ;;
        restart)
            restart_monitoring
            ;;
        logs)
            show_logs
            ;;
        *)
            log_error "Unknown action: $ACTION"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"