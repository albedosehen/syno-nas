#!/bin/bash

# Synology NAS Docker Management - Configuration Validation Script
# This script validates configuration files, environment settings,
# and Docker compose definitions for correctness and security

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Validation tracking
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0
VALIDATION_CHECKS=0
VALIDATION_PASSED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((VALIDATION_PASSED++))
    ((VALIDATION_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((VALIDATION_WARNINGS++))
    ((VALIDATION_CHECKS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((VALIDATION_ERRORS++))
    ((VALIDATION_CHECKS++))
}

log_step() {
    echo -e "${PURPLE}[CHECK]${NC} $1"
}

log_service() {
    echo -e "${CYAN}[SERVICE]${NC} $1"
}

# Help function
show_help() {
    echo "Synology NAS Docker Management - Configuration Validation Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --category CATEGORY      Validate only services in specified category"
    echo "                              (management, media, productivity, networking)"
    echo "  -s, --service SERVICE        Validate only specified service"
    echo "  --config                    Validate global configuration only"
    echo "  --compose                   Validate Docker Compose files only"
    echo "  --environment               Validate environment files only"
    echo "  --security                  Perform security validation checks"
    echo "  --permissions               Validate file and directory permissions"
    echo "  --network                   Validate network configuration"
    echo "  --volumes                   Validate volume configuration"
    echo "  --syntax                    Validate YAML/shell script syntax"
    echo "  --requirements              Check system requirements"
    echo "  --fix-permissions           Automatically fix permission issues"
    echo "  --strict                    Enable strict validation (warnings as errors)"
    echo "  --detailed                  Show detailed validation information"
    echo "  --json                      Output results in JSON format"
    echo "  --report                    Generate validation report"
    echo "  --verbose                   Enable verbose output"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          Validate all configurations"
    echo "  $0 --security --strict      Strict security validation"
    echo "  $0 -c management            Validate only management services"
    echo "  $0 --compose --syntax       Validate only Docker Compose syntax"
    echo "  $0 --fix-permissions        Fix permission issues automatically"
    echo "  $0 --json > validation.json Generate JSON report"
    echo ""
}

# Parse command line arguments
TARGET_CATEGORY=""
TARGET_SERVICE=""
VALIDATE_CONFIG=false
VALIDATE_COMPOSE=false
VALIDATE_ENVIRONMENT=false
VALIDATE_SECURITY=false
VALIDATE_PERMISSIONS=false
VALIDATE_NETWORK=false
VALIDATE_VOLUMES=false
VALIDATE_SYNTAX=false
VALIDATE_REQUIREMENTS=false
FIX_PERMISSIONS=false
STRICT_MODE=false
DETAILED_MODE=false
JSON_OUTPUT=false
GENERATE_REPORT=false
VERBOSE=false
VALIDATE_ALL=true

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
        --config)
            VALIDATE_CONFIG=true
            VALIDATE_ALL=false
            shift
            ;;
        --compose)
            VALIDATE_COMPOSE=true
            VALIDATE_ALL=false
            shift
            ;;
        --environment)
            VALIDATE_ENVIRONMENT=true
            VALIDATE_ALL=false
            shift
            ;;
        --security)
            VALIDATE_SECURITY=true
            VALIDATE_ALL=false
            shift
            ;;
        --permissions)
            VALIDATE_PERMISSIONS=true
            VALIDATE_ALL=false
            shift
            ;;
        --network)
            VALIDATE_NETWORK=true
            VALIDATE_ALL=false
            shift
            ;;
        --volumes)
            VALIDATE_VOLUMES=true
            VALIDATE_ALL=false
            shift
            ;;
        --syntax)
            VALIDATE_SYNTAX=true
            VALIDATE_ALL=false
            shift
            ;;
        --requirements)
            VALIDATE_REQUIREMENTS=true
            VALIDATE_ALL=false
            shift
            ;;
        --fix-permissions)
            FIX_PERMISSIONS=true
            shift
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --detailed)
            DETAILED_MODE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
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

# Enhanced logging with verbose mode
verbose_log() {
    if [ "$VERBOSE" = true ]; then
        log_info "VERBOSE: $1"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate system requirements
validate_system_requirements() {
    if [ "$VALIDATE_REQUIREMENTS" = false ] && [ "$VALIDATE_ALL" = false ]; then
        return 0
    fi
    
    log_step "Validating system requirements..."
    
    # Check Docker
    if command_exists docker; then
        local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        log_success "Docker is installed (version: $docker_version)"
        
        # Check Docker daemon
        if docker info >/dev/null 2>&1; then
            log_success "Docker daemon is running"
        else
            log_error "Docker daemon is not running"
        fi
    else
        log_error "Docker is not installed"
    fi
    
    # Check Docker Compose
    if command_exists docker-compose; then
        local compose_version=$(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)
        log_success "Docker Compose is installed (version: $compose_version)"
    else
        log_error "Docker Compose is not installed"
    fi
    
    # Check disk space
    local available_space=$(df "$PROJECT_ROOT" | awk 'NR==2 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [ "$available_gb" -gt 5 ]; then
        log_success "Sufficient disk space available (${available_gb}GB)"
    elif [ "$available_gb" -gt 1 ]; then
        log_warning "Low disk space available (${available_gb}GB)"
    else
        log_error "Insufficient disk space available (${available_gb}GB)"
    fi
    
    # Check memory
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [ "$total_mem" -gt 2048 ]; then
        log_success "Sufficient memory available (${total_mem}MB)"
    elif [ "$total_mem" -gt 1024 ]; then
        log_warning "Limited memory available (${total_mem}MB)"
    else
        log_error "Insufficient memory available (${total_mem}MB)"
    fi
    
    # Check for Synology-specific paths
    if [ -d "/volume1" ]; then
        log_success "Synology NAS environment detected"
    else
        log_warning "Not running on Synology NAS - some paths may need adjustment"
    fi
}

# Validate global configuration
validate_global_config() {
    if [ "$VALIDATE_CONFIG" = false ] && [ "$VALIDATE_ALL" = false ]; then
        return 0
    fi
    
    log_step "Validating global configuration..."
    
    # Check global .env file
    if [ -f "$ENV_FILE" ]; then
        log_success "Global .env file exists"
        
        # Validate required variables
        local required_vars=("PUID" "PGID" "TZ" "DOCKER_NETWORK_NAME")
        
        source "$ENV_FILE"
        
        for var in "${required_vars[@]}"; do
            if [ -n "${!var}" ]; then
                log_success "Required variable $var is set"
                verbose_log "$var=${!var}"
            else
                log_error "Required variable $var is not set"
            fi
        done
        
        # Validate PUID/PGID format
        if [[ "$PUID" =~ ^[0-9]+$ ]]; then
            log_success "PUID format is valid"
        else
            log_error "PUID must be a numeric value"
        fi
        
        if [[ "$PGID" =~ ^[0-9]+$ ]]; then
            log_success "PGID format is valid"
        else
            log_error "PGID must be a numeric value"
        fi
        
        # Validate timezone
        if [ -f "/usr/share/zoneinfo/$TZ" ] || [ "$TZ" = "UTC" ]; then
            log_success "Timezone $TZ is valid"
        else
            log_warning "Timezone $TZ may not be valid"
        fi
        
    else
        log_error "Global .env file not found"
    fi
    
    # Check .env.example
    if [ -f "$PROJECT_ROOT/.env.example" ]; then
        log_success "Global .env.example file exists"
    else
        log_warning "Global .env.example file not found"
    fi
}

# Validate file permissions
validate_permissions() {
    if [ "$VALIDATE_PERMISSIONS" = false ] && [ "$VALIDATE_ALL" = false ]; then
        return 0
    fi
    
    log_step "Validating file permissions..."
    
    # Check script permissions
    local script_files=$(find "$PROJECT_ROOT/docker/scripts" -name "*.sh" -type f 2>/dev/null)
    
    for script in $script_files; do
        if [ -x "$script" ]; then
            log_success "Script is executable: $(basename "$script")"
        else
            log_error "Script is not executable: $(basename "$script")"
            
            if [ "$FIX_PERMISSIONS" = true ]; then
                chmod +x "$script"
                log_success "Fixed permissions for: $(basename "$script")"
            fi
        fi
    done
    
    # Check .env file permissions
    if [ -f "$ENV_FILE" ]; then
        local env_perms=$(stat -c "%a" "$ENV_FILE")
        if [ "$env_perms" -le 600 ]; then
            log_success ".env file has secure permissions ($env_perms)"
        else
            log_warning ".env file has overly permissive permissions ($env_perms)"
            
            if [ "$FIX_PERMISSIONS" = true ]; then
                chmod 600 "$ENV_FILE"
                log_success "Fixed .env file permissions"
            fi
        fi
    fi
    
    # Check directory permissions
    local data_dir="${DATA_BASE_PATH:-/volume1/docker/data}"
    if [ -d "$data_dir" ]; then
        if [ -w "$data_dir" ]; then
            log_success "Data directory is writable: $data_dir"
        else
            log_error "Data directory is not writable: $data_dir"
        fi
    fi
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

# Validate Docker Compose syntax
validate_compose_syntax() {
    if [ "$VALIDATE_SYNTAX" = false ] && [ "$VALIDATE_COMPOSE" = false ] && [ "$VALIDATE_ALL" = false ]; then
        return 0
    fi
    
    log_step "Validating Docker Compose syntax..."
    
    local services=($(discover_services))
    
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        log_service "Validating $category/$service_name"
        
        cd "$service_dir"
        
        # Check if docker-compose.yml exists
        if [ ! -f "docker-compose.yml" ]; then
            log_error "$category/$service_name: No docker-compose.yml found"
            continue
        fi
        
        # Validate YAML syntax
        if command_exists yamllint; then
            if yamllint docker-compose.yml >/dev/null 2>&1; then
                log_success "$category/$service_name: YAML syntax is valid"
            else
                log_error "$category/$service_name: YAML syntax errors found"
                if [ "$DETAILED_MODE" = true ]; then
                    yamllint docker-compose.yml 2>&1 | head -5
                fi
            fi
        else
            verbose_log "yamllint not available, skipping YAML syntax check"
        fi
        
        # Validate Docker Compose configuration
        if docker-compose config >/dev/null 2>&1; then
            log_success "$category/$service_name: Docker Compose config is valid"
        else
            log_error "$category/$service_name: Docker Compose config is invalid"
            if [ "$DETAILED_MODE" = true ]; then
                docker-compose config 2>&1 | head -3
            fi
        fi
    done
}

# Validate environment files
validate_environment_files() {
    if [ "$VALIDATE_ENVIRONMENT" = false ] && [ "$VALIDATE_ALL" = false ]; then
        return 0
    fi
    
    log_step "Validating service environment files..."
    
    local services=($(discover_services))
    
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        log_service "Validating $category/$service_name environment"
        
        cd "$service_dir"
        
        # Check .env.example
        if [ -f ".env.example" ]; then
            log_success "$category/$service_name: .env.example exists"
            
            # Check for common required variables
            local common_vars=("PUID" "PGID" "TZ")
            
            for var in "${common_vars[@]}"; do
                if grep -q "^$var=" ".env.example"; then
                    log_success "$category/$service_name: $var defined in .env.example"
                else
                    log_warning "$category/$service_name: $var not found in .env.example"
                fi
            done
        else
            log_warning "$category/$service_name: No .env.example file found"
        fi
        
        # Check .env if it exists
        if [ -f ".env" ]; then
            log_success "$category/$service_name: .env file exists"
            
            # Validate .env file permissions
            local env_perms=$(stat -c "%a" ".env")
            if [ "$env_perms" -le 600 ]; then
                log_success "$category/$service_name: .env file has secure permissions"
            else
                log_warning "$category/$service_name: .env file has overly permissive permissions ($env_perms)"
            fi
        else
            log_warning "$category/$service_name: No .env file found (will use .env.example)"
        fi
    done
}

# Validate network configuration
validate_network_config() {
    if [ "$VALIDATE_NETWORK" = false ] && [ "$VALIDATE_ALL" = false ]; then
        return 0
    fi
    
    log_step "Validating network configuration..."
    
    local services=($(discover_services))
    
    # Check for port conflicts
    local used_ports=()
    
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        cd "$service_dir"
        
        if [ -f "docker-compose.yml" ]; then
            # Extract exposed ports
            local ports=$(docker-compose config 2>/dev/null | grep -E "^\s*-\s*[0-9]+:" | sed 's/.*- //' | cut -d: -f1 | sort | uniq)
            
            for port in $ports; do
                if [[ " ${used_ports[@]} " =~ " $port " ]]; then
                    log_error "Port conflict detected: $port used by multiple services"
                else
                    used_ports+=("$port")
                    log_success "$category/$service_name: Port $port is unique"
                fi
            done
        fi
    done
    
    # Check if Docker network exists
    if [ -n "${DOCKER_NETWORK_NAME:-}" ]; then
        if docker network ls | grep -q "$DOCKER_NETWORK_NAME"; then
            log_success "Docker network '$DOCKER_NETWORK_NAME' exists"
        else
            log_warning "Docker network '$DOCKER_NETWORK_NAME' does not exist"
        fi
    fi
}

# Validate volume configuration
validate_volume_config() {
    if [ "$VALIDATE_VOLUMES" = false ] && [ "$VALIDATE_ALL" = false ]; then
        return 0
    fi
    
    log_step "Validating volume configuration..."
    
    local services=($(discover_services))
    
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        cd "$service_dir"
        
        if [ -f "docker-compose.yml" ]; then
            # Check for host volume mounts
            local host_volumes=$(docker-compose config 2>/dev/null | grep -E "^\s*-\s*/\w+" | sed 's/.*- //' | cut -d: -f1)
            
            for volume in $host_volumes; do
                if [ -d "$volume" ]; then
                    log_success "$category/$service_name: Host volume exists: $volume"
                else
                    log_warning "$category/$service_name: Host volume does not exist: $volume"
                fi
            done
        fi
    done
}

# Validate security configuration
validate_security_config() {
    if [ "$VALIDATE_SECURITY" = false ] && [ "$VALIDATE_ALL" = false ]; then
        return 0
    fi
    
    log_step "Validating security configuration..."
    
    local services=($(discover_services))
    
    for service_dir in "${services[@]}"; do
        local service_name=$(basename "$service_dir")
        local category=$(basename "$(dirname "$service_dir")")
        
        cd "$service_dir"
        
        if [ -f "docker-compose.yml" ]; then
            # Check for privileged mode
            if grep -q "privileged.*true" "docker-compose.yml"; then
                log_error "$category/$service_name: Uses privileged mode (security risk)"
            else
                log_success "$category/$service_name: Does not use privileged mode"
            fi
            
            # Check for host network mode
            if grep -q "network_mode.*host" "docker-compose.yml"; then
                log_warning "$category/$service_name: Uses host network mode"
            else
                log_success "$category/$service_name: Uses isolated network mode"
            fi
            
            # Check for bind mounts to sensitive directories
            local sensitive_paths=("/etc" "/var/run" "/proc" "/sys")
            
            for path in "${sensitive_paths[@]}"; do
                if grep -q "$path:" "docker-compose.yml"; then
                    log_warning "$category/$service_name: Mounts sensitive path: $path"
                fi
            done
            
            # Check for exposed ports without local binding
            if grep -E "^\s*-\s*[0-9]+:" "docker-compose.yml" | grep -v "127.0.0.1\|localhost" >/dev/null; then
                log_warning "$category/$service_name: Has ports exposed to all interfaces"
            else
                log_success "$category/$service_name: Ports are properly restricted"
            fi
        fi
    done
}

# Generate validation report
generate_validation_report() {
    if [ "$GENERATE_REPORT" = false ]; then
        return 0
    fi
    
    log_step "Generating validation report..."
    
    local report_file="$PROJECT_ROOT/logs/validation-report-$(date +%Y%m%d_%H%M%S).txt"
    
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
Docker Management Configuration Validation Report
=================================================
Generated: $(date)
Host: $(hostname)

Summary:
- Total Checks: $VALIDATION_CHECKS
- Passed: $VALIDATION_PASSED
- Warnings: $VALIDATION_WARNINGS
- Errors: $VALIDATION_ERRORS
- Success Rate: $(( VALIDATION_PASSED * 100 / VALIDATION_CHECKS ))%

Validation Scope:
- Global Config: $([ "$VALIDATE_CONFIG" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")
- Compose Files: $([ "$VALIDATE_COMPOSE" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")
- Environment: $([ "$VALIDATE_ENVIRONMENT" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")
- Security: $([ "$VALIDATE_SECURITY" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")
- Permissions: $([ "$VALIDATE_PERMISSIONS" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")
- Network: $([ "$VALIDATE_NETWORK" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")
- Volumes: $([ "$VALIDATE_VOLUMES" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")
- Syntax: $([ "$VALIDATE_SYNTAX" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")
- Requirements: $([ "$VALIDATE_REQUIREMENTS" = true ] || [ "$VALIDATE_ALL" = true ] && echo "Yes" || echo "No")

Strict Mode: $STRICT_MODE
Auto-fix Permissions: $FIX_PERMISSIONS

Recommendations:
- Address all errors before deployment
- Review warnings for potential issues
- Run validation after configuration changes
- Use strict mode for production validation

EOF
    
    log_success "Validation report generated: $report_file"
}

# Display validation summary
show_validation_summary() {
    echo ""
    echo "========================================"
    echo "       Validation Summary"
    echo "========================================"
    echo ""
    
    echo "Validation Results:"
    echo "  Total Checks: $VALIDATION_CHECKS"
    echo "  Passed: $VALIDATION_PASSED"
    echo "  Warnings: $VALIDATION_WARNINGS"
    echo "  Errors: $VALIDATION_ERRORS"
    
    if [ $VALIDATION_CHECKS -gt 0 ]; then
        local success_rate=$(( VALIDATION_PASSED * 100 / VALIDATION_CHECKS ))
        echo "  Success Rate: ${success_rate}%"
    fi
    
    echo ""
    
    local overall_status="UNKNOWN"
    if [ $VALIDATION_ERRORS -eq 0 ] && [ $VALIDATION_WARNINGS -eq 0 ]; then
        overall_status="EXCELLENT"
        echo -e "Overall Status: ${GREEN}$overall_status${NC}"
    elif [ $VALIDATION_ERRORS -eq 0 ]; then
        overall_status="GOOD"
        echo -e "Overall Status: ${YELLOW}$overall_status${NC}"
    else
        overall_status="ISSUES FOUND"
        echo -e "Overall Status: ${RED}$overall_status${NC}"
    fi
    
    echo ""
    
    if [ $VALIDATION_ERRORS -gt 0 ] || [ $VALIDATION_WARNINGS -gt 0 ]; then
        echo "Recommendations:"
        echo "  - Review and fix all errors before deployment"
        echo "  - Address warnings to improve configuration quality"
        echo "  - Run validation again after making changes"
        echo "  - Use --detailed flag for more information"
        echo ""
    fi
    
    echo "Next Steps:"
    echo "  - Fix configuration issues: Edit relevant files"
    echo "  - Test deployment: docker/scripts/test-deployment.sh"
    echo "  - Deploy services: docker/scripts/deploy-project.sh"
    echo ""
}

# JSON output function
output_json() {
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"validation_summary\": {"
        echo "    \"total_checks\": $VALIDATION_CHECKS,"
        echo "    \"passed\": $VALIDATION_PASSED,"
        echo "    \"warnings\": $VALIDATION_WARNINGS,"
        echo "    \"errors\": $VALIDATION_ERRORS,"
        echo "    \"success_rate\": $(( VALIDATION_CHECKS > 0 ? VALIDATION_PASSED * 100 / VALIDATION_CHECKS : 0 ))"
        echo "  },"
        echo "  \"configuration\": {"
        echo "    \"strict_mode\": $STRICT_MODE,"
        echo "    \"auto_fix_permissions\": $FIX_PERMISSIONS,"
        echo "    \"target_category\": \"$TARGET_CATEGORY\","
        echo "    \"target_service\": \"$TARGET_SERVICE\""
        echo "  },"
        echo "  \"status\": \"$([ $VALIDATION_ERRORS -eq 0 ] && echo "success" || echo "failure")\""
        echo "}"
    fi
}

# Main execution
main() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo "========================================"
        echo "    Configuration Validation Script"
        echo "========================================"
        echo ""
    fi
    
    cd "$PROJECT_ROOT"
    
    # Load global configuration for validation
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE" 2>/dev/null || true
    fi
    
    # Perform validation checks
    validate_system_requirements
    validate_global_config
    validate_permissions
    validate_compose_syntax
    validate_environment_files
    validate_network_config
    validate_volume_config
    validate_security_config
    
    # Generate outputs
    if [ "$JSON_OUTPUT" = true ]; then
        output_json
    else
        show_validation_summary
        generate_validation_report
    fi
    
    # Exit with appropriate code
    if [ "$STRICT_MODE" = true ]; then
        # In strict mode, warnings are treated as errors
        if [ $VALIDATION_ERRORS -gt 0 ] || [ $VALIDATION_WARNINGS -gt 0 ]; then
            exit 1
        fi
    else
        # Normal mode, only errors cause failure
        if [ $VALIDATION_ERRORS -gt 0 ]; then
            exit 1
        fi
    fi
    
    if [ "$JSON_OUTPUT" = false ]; then
        log_success "Configuration validation completed successfully!"
    fi
}

# Error handling
trap 'log_error "Validation script failed on line $LINENO"' ERR

# Execute main function
main "$@"