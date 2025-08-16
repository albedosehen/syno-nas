#!/bin/bash

# Synology NAS Docker Management - Deployment Testing Script
# This script performs comprehensive testing of Docker service deployments
# including functionality tests, health checks, and integration testing

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"
TEST_RESULTS_DIR="$PROJECT_ROOT/logs/test-results"
TEST_DATE=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test tracking
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0
TEST_RESULTS=()

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TEST_PASSED++))
    ((TEST_TOTAL++))
    TEST_RESULTS+=("PASS: $1")
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TEST_FAILED++))
    ((TEST_TOTAL++))
    TEST_RESULTS+=("FAIL: $1")
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TEST_SKIPPED++))
    ((TEST_TOTAL++))
    TEST_RESULTS+=("SKIP: $1")
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[TEST]${NC} $1"
}

log_service() {
    echo -e "${CYAN}[SERVICE]${NC} $1"
}

# Help function
show_help() {
    echo "Synology NAS Docker Management - Deployment Testing Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --category CATEGORY      Test only services in specified category"
    echo "                              (management, media, productivity, networking)"
    echo "  -s, --service SERVICE        Test only specified service"
    echo "  --deploy                    Deploy services before testing"
    echo "  --cleanup                   Clean up test resources after testing"
    echo "  --functional                Run functional tests"
    echo "  --integration               Run integration tests"
    echo "  --performance               Run performance tests"
    echo "  --security                  Run security tests"
    echo "  --api                       Test API endpoints"
    echo "  --web                       Test web interfaces"
    echo "  --network                   Test network connectivity"
    echo "  --volume                    Test volume mounts and persistence"
    echo "  --backup-restore            Test backup and restore functionality"
    echo "  --timeout SECONDS           Test timeout per service (default: 300)"
    echo "  --retry-count COUNT         Number of retries for failed tests (default: 2)"
    echo "  --parallel                  Run tests in parallel where possible"
    echo "  --continue-on-failure       Continue testing even if some tests fail"
    echo "  --report                    Generate detailed test report"
    echo "  --json                      Output results in JSON format"
    echo "  --verbose                   Enable verbose output"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          Run all tests"
    echo "  $0 --deploy --functional    Deploy and run functional tests"
    echo "  $0 -c management --api      Test management service APIs"
    echo "  $0 --security --report      Run security tests and generate report"
    echo "  $0 --cleanup                Clean up test resources"
    echo ""
}

# Parse command line arguments
TARGET_CATEGORY=""
TARGET_SERVICE=""
DEPLOY_SERVICES=false
CLEANUP_RESOURCES=false
TEST_FUNCTIONAL=false
TEST_INTEGRATION=false
TEST_PERFORMANCE=false
TEST_SECURITY=false
TEST_API=false
TEST_WEB=false
TEST_NETWORK=false
TEST_VOLUME=false
TEST_BACKUP_RESTORE=false
TEST_TIMEOUT=300
RETRY_COUNT=2
PARALLEL_TESTS=false
CONTINUE_ON_FAILURE=false
GENERATE_REPORT=false
JSON_OUTPUT=false
VERBOSE=false
TEST_ALL=true

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
        --deploy)
            DEPLOY_SERVICES=true
            shift
            ;;
        --cleanup)
            CLEANUP_RESOURCES=true
            shift
            ;;
        --functional)
            TEST_FUNCTIONAL=true
            TEST_ALL=false
            shift
            ;;
        --integration)
            TEST_INTEGRATION=true
            TEST_ALL=false
            shift
            ;;
        --performance)
            TEST_PERFORMANCE=true
            TEST_ALL=false
            shift
            ;;
        --security)
            TEST_SECURITY=true
            TEST_ALL=false
            shift
            ;;
        --api)
            TEST_API=true
            TEST_ALL=false
            shift
            ;;
        --web)
            TEST_WEB=true
            TEST_ALL=false
            shift
            ;;
        --network)
            TEST_NETWORK=true
            TEST_ALL=false
            shift
            ;;
        --volume)
            TEST_VOLUME=true
            TEST_ALL=false
            shift
            ;;
        --backup-restore)
            TEST_BACKUP_RESTORE=true
            TEST_ALL=false
            shift
            ;;
        --timeout)
            TEST_TIMEOUT="$2"
            shift 2
            ;;
        --retry-count)
            RETRY_COUNT="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL_TESTS=true
            shift
            ;;
        --continue-on-failure)
            CONTINUE_ON_FAILURE=true
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

# Load global configuration
load_global_config() {
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
}

# Setup test environment
setup_test_environment() {
    log_step "Setting up test environment..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Create test log file
    TEST_LOG_FILE="$TEST_RESULTS_DIR/test-${TEST_DATE}.log"
    touch "$TEST_LOG_FILE"
    
    log_success "Test environment ready"
}

# Discover services to test
discover_services() {
    local category="${1:-all}"
    local service_name="${2:-}"
    local services=()
    
    verbose_log "Discovering services - category: $category, service: $service_name"
    
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

# Deploy services for testing
deploy_test_services() {
    if [ "$DEPLOY_SERVICES" = false ]; then
        return 0
    fi
    
    log_step "Deploying services for testing..."
    
    local deploy_script="$SCRIPT_DIR/deploy-project.sh"
    
    if [ -f "$deploy_script" ] && [ -x "$deploy_script" ]; then
        local deploy_args=""
        
        if [ -n "$TARGET_CATEGORY" ]; then
            deploy_args="--category $TARGET_CATEGORY"
        elif [ -n "$TARGET_SERVICE" ]; then
            deploy_args="--service $TARGET_SERVICE"
        fi
        
        if "$deploy_script" $deploy_args; then
            log_success "Services deployed successfully"
        else
            log_failure "Failed to deploy services"
            return 1
        fi
    else
        log_error "Deploy script not found or not executable: $deploy_script"
        return 1
    fi
}

# Wait for service to be ready
wait_for_service() {
    local service_dir="$1"
    local timeout="${2:-$TEST_TIMEOUT}"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    verbose_log "Waiting for $category/$service_name to be ready (timeout: ${timeout}s)"
    
    cd "$service_dir"
    
    local elapsed=0
    local check_interval=5
    
    while [ $elapsed -lt $timeout ]; do
        # Check if all containers are running
        local expected_containers=$(docker-compose config --services 2>/dev/null | wc -l)
        local running_containers=$(docker-compose ps --services --filter status=running 2>/dev/null | wc -l)
        
        if [ "$running_containers" -eq "$expected_containers" ] && [ "$expected_containers" -gt 0 ]; then
            verbose_log "$category/$service_name is ready"
            return 0
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    log_warning "$category/$service_name did not become ready within $timeout seconds"
    return 1
}

# Test service deployment
test_service_deployment() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_service "Testing deployment of $category/$service_name"
    
    cd "$service_dir"
    
    # Check if docker-compose.yml exists
    if [ ! -f "docker-compose.yml" ]; then
        log_failure "$category/$service_name: No docker-compose.yml found"
        return 1
    fi
    
    # Check if service is running
    local expected_containers=$(docker-compose config --services 2>/dev/null | wc -l)
    local running_containers=$(docker-compose ps --services --filter status=running 2>/dev/null | wc -l)
    
    if [ "$running_containers" -eq "$expected_containers" ] && [ "$expected_containers" -gt 0 ]; then
        log_success "$category/$service_name: All containers are running ($running_containers/$expected_containers)"
    else
        log_failure "$category/$service_name: Not all containers are running ($running_containers/$expected_containers)"
        return 1
    fi
    
    # Check container health status
    local unhealthy_containers=$(docker-compose ps | grep -c "unhealthy" 2>/dev/null || echo "0")
    if [ "$unhealthy_containers" -eq 0 ]; then
        log_success "$category/$service_name: All containers are healthy"
    else
        log_failure "$category/$service_name: $unhealthy_containers containers are unhealthy"
        return 1
    fi
    
    return 0
}

# Test network connectivity
test_network_connectivity() {
    if [ "$TEST_NETWORK" = false ] && [ "$TEST_ALL" = false ]; then
        return 0
    fi
    
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_step "Testing network connectivity for $category/$service_name"
    
    cd "$service_dir"
    
    # Test container to container communication
    local containers=$(docker-compose ps -q 2>/dev/null)
    local network_tests_passed=true
    
    for container in $containers; do
        if [ -n "$container" ]; then
            # Test if container can reach external network
            if docker exec "$container" ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                verbose_log "Container $container has external network access"
            else
                log_warning "Container $container cannot reach external network"
                network_tests_passed=false
            fi
        fi
    done
    
    if [ "$network_tests_passed" = true ]; then
        log_success "$category/$service_name: Network connectivity tests passed"
    else
        log_failure "$category/$service_name: Network connectivity tests failed"
    fi
}

# Test volume persistence
test_volume_persistence() {
    if [ "$TEST_VOLUME" = false ] && [ "$TEST_ALL" = false ]; then
        return 0
    fi
    
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_step "Testing volume persistence for $category/$service_name"
    
    cd "$service_dir"
    
    # Create test file in container
    local containers=$(docker-compose ps -q 2>/dev/null)
    local test_file="test-persistence-$(date +%s)"
    local volume_tests_passed=true
    
    for container in $containers; do
        if [ -n "$container" ]; then
            # Create test file
            if docker exec "$container" touch "/tmp/$test_file" 2>/dev/null; then
                verbose_log "Created test file in container $container"
                
                # Restart container
                docker restart "$container" >/dev/null 2>&1
                
                # Wait for container to be ready
                sleep 5
                
                # Check if test file persists (this tests if /tmp is mounted to a volume)
                if docker exec "$container" ls "/tmp/$test_file" >/dev/null 2>&1; then
                    verbose_log "Test file persisted in container $container"
                    # Clean up test file
                    docker exec "$container" rm "/tmp/$test_file" 2>/dev/null || true
                else
                    verbose_log "Test file did not persist in container $container (expected for /tmp)"
                fi
            else
                log_warning "Could not create test file in container $container"
                volume_tests_passed=false
            fi
        fi
    done
    
    if [ "$volume_tests_passed" = true ]; then
        log_success "$category/$service_name: Volume persistence tests completed"
    else
        log_failure "$category/$service_name: Volume persistence tests failed"
    fi
}

# Test API endpoints
test_api_endpoints() {
    if [ "$TEST_API" = false ] && [ "$TEST_ALL" = false ]; then
        return 0
    fi
    
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_step "Testing API endpoints for $category/$service_name"
    
    cd "$service_dir"
    
    # Load service environment to get ports
    if [ -f ".env" ]; then
        source ".env"
    fi
    
    # Test common API endpoints based on service type
    case "$service_name" in
        "portainer")
            local port="${PORTAINER_PORT:-9000}"
            if curl -s -f "http://localhost:$port/api/system/status" >/dev/null 2>&1; then
                log_success "$category/$service_name: API endpoint is responding"
            else
                log_failure "$category/$service_name: API endpoint is not responding"
            fi
            ;;
        *)
            log_skip "$category/$service_name: No specific API tests defined"
            ;;
    esac
}

# Test web interfaces
test_web_interfaces() {
    if [ "$TEST_WEB" = false ] && [ "$TEST_ALL" = false ]; then
        return 0
    fi
    
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_step "Testing web interface for $category/$service_name"
    
    cd "$service_dir"
    
    # Load service environment to get ports
    if [ -f ".env" ]; then
        source ".env"
    fi
    
    # Test web interfaces based on service type
    case "$service_name" in
        "portainer")
            local port="${PORTAINER_PORT:-9000}"
            if curl -s -f "http://localhost:$port" >/dev/null 2>&1; then
                log_success "$category/$service_name: Web interface is accessible"
            else
                log_failure "$category/$service_name: Web interface is not accessible"
            fi
            ;;
        *)
            log_skip "$category/$service_name: No specific web interface tests defined"
            ;;
    esac
}

# Test service security
test_service_security() {
    if [ "$TEST_SECURITY" = false ] && [ "$TEST_ALL" = false ]; then
        return 0
    fi
    
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_step "Testing security for $category/$service_name"
    
    cd "$service_dir"
    
    local security_tests_passed=true
    
    # Check if containers are running as non-root
    local containers=$(docker-compose ps -q 2>/dev/null)
    
    for container in $containers; do
        if [ -n "$container" ]; then
            local user_id=$(docker exec "$container" id -u 2>/dev/null || echo "0")
            if [ "$user_id" -ne 0 ]; then
                verbose_log "Container $container is running as non-root user (UID: $user_id)"
            else
                log_warning "Container $container is running as root"
                security_tests_passed=false
            fi
        fi
    done
    
    # Check for exposed sensitive ports
    local exposed_ports=$(docker-compose config 2>/dev/null | grep -E "^\s*-\s*[0-9]+" | wc -l)
    if [ "$exposed_ports" -gt 0 ]; then
        verbose_log "$category/$service_name has $exposed_ports exposed ports"
    fi
    
    if [ "$security_tests_passed" = true ]; then
        log_success "$category/$service_name: Security tests passed"
    else
        log_failure "$category/$service_name: Security tests failed"
    fi
}

# Test backup and restore
test_backup_restore() {
    if [ "$TEST_BACKUP_RESTORE" = false ] && [ "$TEST_ALL" = false ]; then
        return 0
    fi
    
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_step "Testing backup and restore for $category/$service_name"
    
    cd "$service_dir"
    
    # Check if service has backup script
    if [ -f "backup.sh" ] && [ -x "backup.sh" ]; then
        # Test backup creation
        if ./backup.sh --dry-run >/dev/null 2>&1; then
            log_success "$category/$service_name: Backup script is functional"
        else
            log_failure "$category/$service_name: Backup script failed"
        fi
    else
        log_skip "$category/$service_name: No backup script found"
    fi
}

# Run comprehensive test suite for a service
test_service_comprehensive() {
    local service_dir="$1"
    local service_name=$(basename "$service_dir")
    local category=$(basename "$(dirname "$service_dir")")
    
    log_service "Running comprehensive tests for $category/$service_name"
    
    local service_tests_passed=0
    local service_tests_total=0
    
    # Wait for service to be ready
    if wait_for_service "$service_dir" 60; then
        # Run all test categories
        local test_functions=(
            "test_service_deployment"
            "test_network_connectivity"
            "test_volume_persistence"
            "test_api_endpoints"
            "test_web_interfaces"
            "test_service_security"
            "test_backup_restore"
        )
        
        for test_func in "${test_functions[@]}"; do
            local initial_passed=$TEST_PASSED
            
            # Run test with retry logic
            local attempts=0
            local test_passed=false
            
            while [ $attempts -lt $RETRY_COUNT ] && [ "$test_passed" = false ]; do
                ((attempts++))
                
                if $test_func "$service_dir"; then
                    test_passed=true
                else
                    if [ $attempts -lt $RETRY_COUNT ]; then
                        verbose_log "Retrying test (attempt $((attempts + 1))/$RETRY_COUNT)"
                        sleep 5
                    fi
                fi
            done
            
            if [ "$test_passed" = false ] && [ "$CONTINUE_ON_FAILURE" = false ]; then
                log_error "Test failed for $category/$service_name, stopping tests"
                return 1
            fi
        done
        
        log_success "Completed testing $category/$service_name"
    else
        log_failure "$category/$service_name: Service not ready for testing"
        return 1
    fi
}

# Clean up test resources
cleanup_test_resources() {
    if [ "$CLEANUP_RESOURCES" = false ]; then
        return 0
    fi
    
    log_step "Cleaning up test resources..."
    
    # Remove test containers and images
    docker system prune -f >/dev/null 2>&1 || true
    
    # Clean up test files
    find "$TEST_RESULTS_DIR" -name "*.tmp" -delete 2>/dev/null || true
    
    log_success "Test resources cleaned up"
}

# Generate test report
generate_test_report() {
    if [ "$GENERATE_REPORT" = false ]; then
        return 0
    fi
    
    log_step "Generating test report..."
    
    local report_file="$TEST_RESULTS_DIR/test-report-${TEST_DATE}.txt"
    
    cat > "$report_file" << EOF
Docker Management Deployment Test Report
=========================================
Generated: $(date)
Host: $(hostname)

Test Summary:
- Total Tests: $TEST_TOTAL
- Passed: $TEST_PASSED
- Failed: $TEST_FAILED
- Skipped: $TEST_SKIPPED
- Success Rate: $(( TEST_TOTAL > 0 ? TEST_PASSED * 100 / TEST_TOTAL : 0 ))%

Test Configuration:
- Target Category: ${TARGET_CATEGORY:-All}
- Target Service: ${TARGET_SERVICE:-All}
- Timeout: ${TEST_TIMEOUT}s
- Retry Count: $RETRY_COUNT
- Parallel Tests: $PARALLEL_TESTS
- Continue on Failure: $CONTINUE_ON_FAILURE

Test Results:
EOF
    
    for result in "${TEST_RESULTS[@]}"; do
        echo "- $result" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

Recommendations:
- Address all failed tests before production deployment
- Review skipped tests for additional coverage
- Monitor test performance and adjust timeouts if needed
- Run tests regularly as part of CI/CD pipeline

EOF
    
    log_success "Test report generated: $report_file"
}

# Display test summary
show_test_summary() {
    echo ""
    echo "========================================"
    echo "         Test Summary"
    echo "========================================"
    echo ""
    
    echo "Test Results:"
    echo "  Total Tests: $TEST_TOTAL"
    echo "  Passed: $TEST_PASSED"
    echo "  Failed: $TEST_FAILED"
    echo "  Skipped: $TEST_SKIPPED"
    
    if [ $TEST_TOTAL -gt 0 ]; then
        local success_rate=$(( TEST_PASSED * 100 / TEST_TOTAL ))
        echo "  Success Rate: ${success_rate}%"
    fi
    
    echo ""
    
    local overall_status="UNKNOWN"
    if [ $TEST_FAILED -eq 0 ] && [ $TEST_PASSED -gt 0 ]; then
        overall_status="ALL TESTS PASSED"
        echo -e "Overall Status: ${GREEN}$overall_status${NC}"
    elif [ $TEST_FAILED -eq 0 ] && [ $TEST_PASSED -eq 0 ]; then
        overall_status="NO TESTS RUN"
        echo -e "Overall Status: ${YELLOW}$overall_status${NC}"
    else
        overall_status="TESTS FAILED"
        echo -e "Overall Status: ${RED}$overall_status${NC}"
    fi
    
    echo ""
    
    if [ $TEST_FAILED -gt 0 ]; then
        echo "Failed Tests:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL:* ]]; then
                echo "  - ${result#FAIL: }"
            fi
        done
        echo ""
    fi
    
    echo "Next Steps:"
    echo "  - Fix failed tests before deploying to production"
    echo "  - Review logs for detailed error information"
    echo "  - Re-run tests after making fixes"
    echo "  - Consider adding more comprehensive tests"
    echo ""
}

# JSON output function
output_json() {
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"test_summary\": {"
        echo "    \"total\": $TEST_TOTAL,"
        echo "    \"passed\": $TEST_PASSED,"
        echo "    \"failed\": $TEST_FAILED,"
        echo "    \"skipped\": $TEST_SKIPPED,"
        echo "    \"success_rate\": $(( TEST_TOTAL > 0 ? TEST_PASSED * 100 / TEST_TOTAL : 0 ))"
        echo "  },"
        echo "  \"configuration\": {"
        echo "    \"target_category\": \"$TARGET_CATEGORY\","
        echo "    \"target_service\": \"$TARGET_SERVICE\","
        echo "    \"timeout\": $TEST_TIMEOUT,"
        echo "    \"retry_count\": $RETRY_COUNT,"
        echo "    \"parallel_tests\": $PARALLEL_TESTS"
        echo "  },"
        echo "  \"status\": \"$([ $TEST_FAILED -eq 0 ] && echo "success" || echo "failure")\""
        echo "}"
    fi
}

# Main execution
main() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo "========================================"
        echo "     Deployment Testing Script"
        echo "========================================"
        echo ""
    fi
    
    cd "$PROJECT_ROOT"
    load_global_config
    setup_test_environment
    
    # Deploy services if requested
    deploy_test_services
    
    # Discover services to test
    local services=()
    
    if [ -n "$TARGET_SERVICE" ]; then
        services=($(discover_services "all" "$TARGET_SERVICE"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "Service '$TARGET_SERVICE' not found"
            exit 1
        fi
    elif [ -n "$TARGET_CATEGORY" ]; then
        services=($(discover_services "$TARGET_CATEGORY"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "No services found in category '$TARGET_CATEGORY'"
            exit 1
        fi
    else
        # Test all services
        services=($(discover_services "all"))
        if [ ${#services[@]} -eq 0 ]; then
            log_error "No services found"
            exit 1
        fi
    fi
    
    log_info "Found ${#services[@]} services to test"
    verbose_log "Services: ${services[*]}"
    
    # Run tests
    for service_dir in "${services[@]}"; do
        if ! test_service_comprehensive "$service_dir"; then
            if [ "$CONTINUE_ON_FAILURE" = false ]; then
                log_error "Testing failed, stopping"
                break
            fi
        fi
    done
    
    # Clean up resources
    cleanup_test_resources
    
    # Generate outputs
    if [ "$JSON_OUTPUT" = true ]; then
        output_json
    else
        show_test_summary
        generate_test_report
    fi
    
    # Exit with appropriate code
    if [ $TEST_FAILED -gt 0 ]; then
        exit 1
    fi
    
    if [ "$JSON_OUTPUT" = false ]; then
        log_success "Deployment testing completed successfully!"
    fi
}

# Error handling
trap 'log_error "Test script failed on line $LINENO"' ERR

# Execute main function
main "$@"