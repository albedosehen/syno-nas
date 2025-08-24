#!/bin/bash
set -euo pipefail

# ===========================================
# CORE SERVICES SCRIPT TESTING SUITE
# ===========================================
# Comprehensive testing for all automation scripts
# Validates error handling, usage information, and functionality
# Platform: Linux/Synology DSM 7.2+
#
# Usage: ./test-scripts.sh [OPTIONS]
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

# Test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly TEST_LOG="${SCRIPT_DIR}/test-results.log"
readonly TEST_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Global test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test flags
VERBOSE=false
QUICK_TEST=false
SKIP_DEPS=false
GENERATE_REPORT=true

# Scripts to test
readonly SCRIPTS_TO_TEST=(
    "deploy.sh"
    "deploy.ps1"
    "stop.sh"
    "backup.sh"
    "logs.sh"
    "status.sh"
    "update.sh"
)

# Logging functions
log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $(date '+%H:%M:%S') - $message" | tee -a "$TEST_LOG"
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') - $message" | tee -a "$TEST_LOG"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') - $message" | tee -a "$TEST_LOG"
}

log_debug() {
    local message="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%H:%M:%S') - $message" | tee -a "$TEST_LOG"
    fi
}

log_test() {
    local status="$1"
    local test_name="$2"
    local details="$3"
    
    case "$status" in
        "PASS")
            echo -e "${GREEN}✅ PASS${NC} - $test_name" | tee -a "$TEST_LOG"
            ((TESTS_PASSED++))
            ;;
        "FAIL")
            echo -e "${RED}❌ FAIL${NC} - $test_name" | tee -a "$TEST_LOG"
            if [[ -n "$details" ]]; then
                echo -e "  ${RED}Details:${NC} $details" | tee -a "$TEST_LOG"
            fi
            ((TESTS_FAILED++))
            ;;
        "SKIP")
            echo -e "${YELLOW}⏭️  SKIP${NC} - $test_name" | tee -a "$TEST_LOG"
            if [[ -n "$details" ]]; then
                echo -e "  ${YELLOW}Reason:${NC} $details" | tee -a "$TEST_LOG"
            fi
            ((TESTS_SKIPPED++))
            ;;
    esac
    ((TESTS_TOTAL++))
}

# Help function
show_help() {
    cat << EOF
${CYAN}Core Services Script Testing Suite${NC}

${YELLOW}USAGE:${NC}
    $0 [OPTIONS]

${YELLOW}DESCRIPTION:${NC}
    Comprehensive testing suite for all core services automation scripts.
    Validates error handling, usage information, parameter validation,
    and basic functionality of all deployment and management scripts.

${YELLOW}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -q, --quick             Quick test mode (skip long-running tests)
    -s, --skip-deps         Skip dependency checks
    -r, --no-report         Don't generate detailed test report
    
${YELLOW}TEST CATEGORIES:${NC}
    • File existence and permissions
    • Help/usage information availability
    • Parameter validation and error handling
    • Dry-run functionality
    • Logging and output consistency
    • Basic functionality validation

${YELLOW}EXAMPLES:${NC}
    $0                      # Run full test suite
    $0 -v                   # Verbose testing
    $0 -q                   # Quick test mode
    $0 --skip-deps          # Skip dependency validation

${YELLOW}OUTPUT:${NC}
    Test results are logged to: $TEST_LOG
    Detailed report generated after completion

For more information, see README.md
EOF
}

# Initialize test environment
initialize_test_environment() {
    log_info "Initializing test environment..."
    
    # Create test log
    echo "=== CORE SERVICES SCRIPT TESTING - $TEST_TIMESTAMP ===" > "$TEST_LOG"
    echo "Test started at: $(date)" >> "$TEST_LOG"
    echo "Test directory: $SCRIPT_DIR" >> "$TEST_LOG"
    echo >> "$TEST_LOG"
    
    # Validate test environment
    if [[ ! -d "$SCRIPT_DIR" ]]; then
        log_error "Script directory not found: $SCRIPT_DIR"
        exit 1
    fi
    
    cd "$SCRIPT_DIR"
    log_debug "Changed to script directory: $(pwd)"
    
    log_info "Test environment initialized successfully"
}

# Test file existence and permissions
test_file_existence() {
    local script="$1"
    
    log_debug "Testing file existence for: $script"
    
    if [[ ! -f "$script" ]]; then
        log_test "FAIL" "File existence: $script" "File does not exist"
        return 1
    fi
    
    log_test "PASS" "File existence: $script" ""
    return 0
}

test_file_permissions() {
    local script="$1"
    
    log_debug "Testing file permissions for: $script"
    
    if [[ ! -x "$script" ]]; then
        log_test "FAIL" "File permissions: $script" "Script is not executable"
        return 1
    fi
    
    log_test "PASS" "File permissions: $script" ""
    return 0
}

# Test help/usage information
test_help_information() {
    local script="$1"
    
    log_debug "Testing help information for: $script"
    
    # Skip PowerShell scripts on Linux
    if [[ "$script" == *.ps1 ]] && [[ "$(uname)" != "CYGWIN"* ]] && [[ "$(uname)" != "MINGW"* ]]; then
        log_test "SKIP" "Help information: $script" "PowerShell script on non-Windows system"
        return 0
    fi
    
    # Test --help option
    local help_output
    if [[ "$script" == *.ps1 ]]; then
        # PowerShell script
        if command -v pwsh &> /dev/null; then
            help_output=$(pwsh -File "$script" -Help 2>&1 || true)
        else
            log_test "SKIP" "Help information: $script" "PowerShell not available"
            return 0
        fi
    else
        # Bash script
        help_output=$(bash "$script" --help 2>&1 || true)
    fi
    
    # Check if help output contains expected sections
    local required_sections=("USAGE" "DESCRIPTION" "OPTIONS" "EXAMPLES")
    local missing_sections=()
    
    for section in "${required_sections[@]}"; do
        if ! echo "$help_output" | grep -q "$section"; then
            missing_sections+=("$section")
        fi
    done
    
    if [[ ${#missing_sections[@]} -gt 0 ]]; then
        log_test "FAIL" "Help information: $script" "Missing sections: ${missing_sections[*]}"
        return 1
    fi
    
    log_test "PASS" "Help information: $script" ""
    return 0
}

# Test parameter validation
test_parameter_validation() {
    local script="$1"
    
    log_debug "Testing parameter validation for: $script"
    
    # Skip PowerShell scripts on Linux
    if [[ "$script" == *.ps1 ]] && [[ "$(uname)" != "CYGWIN"* ]] && [[ "$(uname)" != "MINGW"* ]]; then
        log_test "SKIP" "Parameter validation: $script" "PowerShell script on non-Windows system"
        return 0
    fi
    
    # Test invalid parameter
    local invalid_output
    if [[ "$script" == *.ps1 ]]; then
        if command -v pwsh &> /dev/null; then
            invalid_output=$(pwsh -File "$script" --invalid-parameter 2>&1 || true)
        else
            log_test "SKIP" "Parameter validation: $script" "PowerShell not available"
            return 0
        fi
    else
        invalid_output=$(bash "$script" --invalid-parameter 2>&1 || true)
    fi
    
    # Should contain error message for invalid parameter
    if ! echo "$invalid_output" | grep -q -i "unknown\|invalid\|error"; then
        log_test "FAIL" "Parameter validation: $script" "No error message for invalid parameter"
        return 1
    fi
    
    log_test "PASS" "Parameter validation: $script" ""
    return 0
}

# Test dry-run functionality
test_dry_run_functionality() {
    local script="$1"
    
    log_debug "Testing dry-run functionality for: $script"
    
    # Skip PowerShell scripts on Linux
    if [[ "$script" == *.ps1 ]] && [[ "$(uname)" != "CYGWIN"* ]] && [[ "$(uname)" != "MINGW"* ]]; then
        log_test "SKIP" "Dry-run functionality: $script" "PowerShell script on non-Windows system"
        return 0
    fi
    
    # Check if script supports dry-run
    local help_output
    if [[ "$script" == *.ps1 ]]; then
        if command -v pwsh &> /dev/null; then
            help_output=$(pwsh -File "$script" -Help 2>&1 || true)
        else
            log_test "SKIP" "Dry-run functionality: $script" "PowerShell not available"
            return 0
        fi
    else
        help_output=$(bash "$script" --help 2>&1 || true)
    fi
    
    if ! echo "$help_output" | grep -q -i "dry.run\|--dry-run\|-d"; then
        log_test "SKIP" "Dry-run functionality: $script" "Script does not support dry-run"
        return 0
    fi
    
    # Test dry-run execution
    local dry_run_output
    if [[ "$script" == *.ps1 ]]; then
        dry_run_output=$(timeout 30 pwsh -File "$script" -DryRun 2>&1 || true)
    else
        dry_run_output=$(timeout 30 bash "$script" --dry-run 2>&1 || true)
    fi
    
    # Check if dry-run indicates no actual changes
    if echo "$dry_run_output" | grep -q -i "would\|dry.run\|no changes"; then
        log_test "PASS" "Dry-run functionality: $script" ""
    else
        log_test "FAIL" "Dry-run functionality: $script" "Dry-run output doesn't indicate simulation"
        return 1
    fi
    
    return 0
}

# Test error handling
test_error_handling() {
    local script="$1"
    
    log_debug "Testing error handling for: $script"
    
    # Skip PowerShell scripts on Linux
    if [[ "$script" == *.ps1 ]] && [[ "$(uname)" != "CYGWIN"* ]] && [[ "$(uname)" != "MINGW"* ]]; then
        log_test "SKIP" "Error handling: $script" "PowerShell script on non-Windows system"
        return 0
    fi
    
    # Test with missing required files/dependencies
    local temp_env_backup=""
    if [[ -f ".env" ]]; then
        temp_env_backup=$(mktemp)
        cp ".env" "$temp_env_backup"
        rm ".env"
    fi
    
    local error_output
    local exit_code
    
    if [[ "$script" == *.ps1 ]]; then
        if command -v pwsh &> /dev/null; then
            error_output=$(timeout 10 pwsh -File "$script" 2>&1 || true)
            exit_code=$?
        else
            log_test "SKIP" "Error handling: $script" "PowerShell not available"
            return 0
        fi
    else
        error_output=$(timeout 10 bash "$script" 2>&1 || true)
        exit_code=$?
    fi
    
    # Restore environment file if backed up
    if [[ -n "$temp_env_backup" && -f "$temp_env_backup" ]]; then
        cp "$temp_env_backup" ".env"
        rm "$temp_env_backup"
    fi
    
    # Check if script properly handles missing dependencies
    if [[ $exit_code -eq 0 ]]; then
        log_test "FAIL" "Error handling: $script" "Script should fail with missing dependencies"
        return 1
    fi
    
    # Check if error message is informative
    if ! echo "$error_output" | grep -q -i "error\|missing\|not found\|failed"; then
        log_test "FAIL" "Error handling: $script" "No informative error message"
        return 1
    fi
    
    log_test "PASS" "Error handling: $script" ""
    return 0
}

# Test logging consistency
test_logging_consistency() {
    local script="$1"
    
    log_debug "Testing logging consistency for: $script"
    
    # Skip PowerShell scripts on Linux
    if [[ "$script" == *.ps1 ]] && [[ "$(uname)" != "CYGWIN"* ]] && [[ "$(uname)" != "MINGW"* ]]; then
        log_test "SKIP" "Logging consistency: $script" "PowerShell script on non-Windows system"
        return 0
    fi
    
    # Check if script uses consistent logging patterns
    local script_content
    script_content=$(cat "$script")
    
    # Check for logging functions
    local has_logging=false
    if echo "$script_content" | grep -q "log_info\|log_warn\|log_error\|log_debug"; then
        has_logging=true
    elif echo "$script_content" | grep -q "Write-Host\|Write-Warning\|Write-Error"; then
        has_logging=true
    elif echo "$script_content" | grep -q "echo.*\[\(INFO\|WARN\|ERROR\)\]"; then
        has_logging=true
    fi
    
    if ! $has_logging; then
        log_test "FAIL" "Logging consistency: $script" "No consistent logging functions found"
        return 1
    fi
    
    log_test "PASS" "Logging consistency: $script" ""
    return 0
}

# Test script-specific functionality
test_specific_functionality() {
    local script="$1"
    
    log_debug "Testing specific functionality for: $script"
    
    case "$script" in
        "deploy.sh"|"deploy.ps1")
            test_deploy_functionality "$script"
            ;;
        "stop.sh")
            test_stop_functionality "$script"
            ;;
        "backup.sh")
            test_backup_functionality "$script"
            ;;
        "logs.sh")
            test_logs_functionality "$script"
            ;;
        "status.sh")
            test_status_functionality "$script"
            ;;
        "update.sh")
            test_update_functionality "$script"
            ;;
        *)
            log_test "SKIP" "Specific functionality: $script" "No specific tests defined"
            ;;
    esac
}

test_deploy_functionality() {
    local script="$1"
    
    # Skip PowerShell scripts on Linux
    if [[ "$script" == *.ps1 ]] && [[ "$(uname)" != "CYGWIN"* ]] && [[ "$(uname)" != "MINGW"* ]]; then
        log_test "SKIP" "Deploy functionality: $script" "PowerShell script on non-Windows system"
        return 0
    fi
    
    # Test prerequisite checking
    local prereq_output
    if [[ "$script" == *.ps1 ]]; then
        if command -v pwsh &> /dev/null; then
            prereq_output=$(timeout 10 pwsh -File "$script" -DryRun 2>&1 || true)
        else
            log_test "SKIP" "Deploy functionality: $script" "PowerShell not available"
            return 0
        fi
    else
        prereq_output=$(timeout 10 bash "$script" --dry-run 2>&1 || true)
    fi
    
    if echo "$prereq_output" | grep -q -i "prerequisite\|requirement\|check"; then
        log_test "PASS" "Deploy functionality: $script" ""
    else
        log_test "FAIL" "Deploy functionality: $script" "No prerequisite checking detected"
        return 1
    fi
    
    return 0
}

test_stop_functionality() {
    local script="$1"
    
    # Test help options
    local help_output
    help_output=$(bash "$script" --help 2>&1 || true)
    
    if echo "$help_output" | grep -q -i "graceful\|force\|remove"; then
        log_test "PASS" "Stop functionality: $script" ""
    else
        log_test "FAIL" "Stop functionality: $script" "Missing stop options in help"
        return 1
    fi
    
    return 0
}

test_backup_functionality() {
    local script="$1"
    
    # Test backup types
    local help_output
    help_output=$(bash "$script" --help 2>&1 || true)
    
    if echo "$help_output" | grep -q -i "full\|data\|config"; then
        log_test "PASS" "Backup functionality: $script" ""
    else
        log_test "FAIL" "Backup functionality: $script" "Missing backup types in help"
        return 1
    fi
    
    return 0
}

test_logs_functionality() {
    local script="$1"
    
    # Test log filtering options
    local help_output
    help_output=$(bash "$script" --help 2>&1 || true)
    
    if echo "$help_output" | grep -q -i "follow\|level\|export"; then
        log_test "PASS" "Logs functionality: $script" ""
    else
        log_test "FAIL" "Logs functionality: $script" "Missing log options in help"
        return 1
    fi
    
    return 0
}

test_status_functionality() {
    local script="$1"
    
    # Test status monitoring options
    local help_output
    help_output=$(bash "$script" --help 2>&1 || true)
    
    if echo "$help_output" | grep -q -i "watch\|diagnose\|alert"; then
        log_test "PASS" "Status functionality: $script" ""
    else
        log_test "FAIL" "Status functionality: $script" "Missing status options in help"
        return 1
    fi
    
    return 0
}

test_update_functionality() {
    local script="$1"
    
    # Test update options
    local help_output
    help_output=$(bash "$script" --help 2>&1 || true)
    
    if echo "$help_output" | grep -q -i "safe\|latest\|force"; then
        log_test "PASS" "Update functionality: $script" ""
    else
        log_test "FAIL" "Update functionality: $script" "Missing update types in help"
        return 1
    fi
    
    return 0
}

# Test documentation files
test_documentation() {
    log_info "Testing documentation files..."
    
    local docs=("README.md" "DOPPLER_SETUP.md" "MIGRATION.md" "MONITORING.md")
    
    for doc in "${docs[@]}"; do
        if [[ -f "$doc" ]]; then
            # Check file size (should not be empty)
            local file_size
            file_size=$(stat -c%s "$doc")
            if [[ $file_size -gt 1000 ]]; then
                log_test "PASS" "Documentation: $doc" ""
            else
                log_test "FAIL" "Documentation: $doc" "File too small (${file_size} bytes)"
            fi
            
            # Check for basic sections
            if grep -q "Table of Contents\|Overview\|Prerequisites" "$doc"; then
                log_test "PASS" "Documentation structure: $doc" ""
            else
                log_test "FAIL" "Documentation structure: $doc" "Missing basic sections"
            fi
        else
            log_test "FAIL" "Documentation: $doc" "File not found"
        fi
    done
}

# Test configuration files
test_configuration() {
    log_info "Testing configuration files..."
    
    # Test .env.example
    if [[ -f ".env.example" ]]; then
        local required_vars=("DOPPLER_TOKEN" "PORTAINER_PORT" "SURREALDB_PORT" "PUID" "PGID")
        local missing_vars=()
        
        for var in "${required_vars[@]}"; do
            if ! grep -q "^${var}=" ".env.example"; then
                missing_vars+=("$var")
            fi
        done
        
        if [[ ${#missing_vars[@]} -eq 0 ]]; then
            log_test "PASS" "Configuration: .env.example" ""
        else
            log_test "FAIL" "Configuration: .env.example" "Missing variables: ${missing_vars[*]}"
        fi
    else
        log_test "FAIL" "Configuration: .env.example" "File not found"
    fi
    
    # Test docker-compose.yml
    if [[ -f "docker-compose.yml" ]]; then
        if command -v docker-compose &> /dev/null; then
            if docker-compose config &> /dev/null; then
                log_test "PASS" "Configuration: docker-compose.yml" ""
            else
                log_test "FAIL" "Configuration: docker-compose.yml" "Invalid YAML structure"
            fi
        else
            log_test "SKIP" "Configuration: docker-compose.yml" "docker-compose not available"
        fi
    else
        log_test "FAIL" "Configuration: docker-compose.yml" "File not found"
    fi
}

# Test dependencies
test_dependencies() {
    if [[ "$SKIP_DEPS" == true ]]; then
        log_info "Skipping dependency tests..."
        return 0
    fi
    
    log_info "Testing system dependencies..."
    
    local required_commands=("docker" "curl" "tar" "grep" "awk" "sed")
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            log_test "PASS" "Dependency: $cmd" ""
        else
            log_test "FAIL" "Dependency: $cmd" "Command not found"
        fi
    done
    
    # Test Docker specifically
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            log_test "PASS" "Docker daemon" ""
        else
            log_test "FAIL" "Docker daemon" "Not running or not accessible"
        fi
    fi
}

# Generate comprehensive test report
generate_test_report() {
    if [[ "$GENERATE_REPORT" == false ]]; then
        return 0
    fi
    
    local report_file="${SCRIPT_DIR}/test-report-${TEST_TIMESTAMP}.html"
    
    log_info "Generating comprehensive test report: $report_file"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Core Services Script Testing Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1, h2 { color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .stat-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-number { font-size: 2.5em; font-weight: bold; margin-bottom: 10px; }
        .stat-label { font-size: 1.1em; opacity: 0.9; }
        .pass { color: #28a745; font-weight: bold; }
        .fail { color: #dc3545; font-weight: bold; }
        .skip { color: #ffc107; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f8f9fa; font-weight: bold; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        .test-details { margin: 20px 0; }
        .timestamp { color: #666; font-style: italic; }
        .section { margin: 30px 0; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 4px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧪 Core Services Script Testing Report</h1>
        <p class="timestamp">Generated: $(date)</p>
        <p class="timestamp">Test Duration: ${TEST_TIMESTAMP}</p>
        
        <div class="summary">
            <div class="stat-card">
                <div class="stat-number">$TESTS_TOTAL</div>
                <div class="stat-label">Total Tests</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$TESTS_PASSED</div>
                <div class="stat-label">Passed</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$TESTS_FAILED</div>
                <div class="stat-label">Failed</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$TESTS_SKIPPED</div>
                <div class="stat-label">Skipped</div>
            </div>
        </div>
        
        <div class="section">
            <h2>📊 Test Results Summary</h2>
            <table>
                <thead>
                    <tr>
                        <th>Test Category</th>
                        <th>Status</th>
                        <th>Details</th>
                    </tr>
                </thead>
                <tbody>
EOF

    # Parse test log for results
    while IFS= read -r line; do
        if [[ "$line" =~ (PASS|FAIL|SKIP).*-.*(.+) ]]; then
            local status=$(echo "$line" | grep -oE "(PASS|FAIL|SKIP)")
            local test_name=$(echo "$line" | sed 's/.*- //')
            local css_class="pass"
            
            case "$status" in
                "FAIL") css_class="fail" ;;
                "SKIP") css_class="skip" ;;
            esac
            
            echo "                    <tr>" >> "$report_file"
            echo "                        <td>$test_name</td>" >> "$report_file"
            echo "                        <td class=\"$css_class\">$status</td>" >> "$report_file"
            echo "                        <td>-</td>" >> "$report_file"
            echo "                    </tr>" >> "$report_file"
        fi
    done < "$TEST_LOG"

    cat >> "$report_file" << EOF
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>📝 Full Test Log</h2>
            <pre>$(cat "$TEST_LOG")</pre>
        </div>
        
        <div class="section">
            <h2>🔧 Recommendations</h2>
            <ul>
EOF

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "                <li><strong>Address Failed Tests:</strong> Review and fix the $TESTS_FAILED failed test(s) before deployment.</li>" >> "$report_file"
    fi
    
    if [[ $TESTS_SKIPPED -gt 5 ]]; then
        echo "                <li><strong>Review Skipped Tests:</strong> Consider addressing the $TESTS_SKIPPED skipped test(s) for complete validation.</li>" >> "$report_file"
    fi
    
    echo "                <li><strong>Regular Testing:</strong> Run this test suite regularly to ensure script quality.</li>" >> "$report_file"
    echo "                <li><strong>Documentation:</strong> Keep documentation updated as scripts evolve.</li>" >> "$report_file"

    cat >> "$report_file" << EOF
            </ul>
        </div>
        
        <div class="section">
            <p class="timestamp">Report generated by Core Services Testing Suite v1.0.0</p>
        </div>
    </div>
</body>
</html>
EOF

    log_info "Test report generated: $report_file"
}

# Run tests for a single script
run_script_tests() {
    local script="$1"
    
    log_info "Testing script: $script"
    
    # Basic tests
    test_file_existence "$script"
    test_file_permissions "$script"
    test_help_information "$script"
    test_parameter_validation "$script"
    test_logging_consistency "$script"
    
    # Advanced tests (skip in quick mode)
    if [[ "$QUICK_TEST" == false ]]; then
        test_dry_run_functionality "$script"
        test_error_handling "$script"
        test_specific_functionality "$script"
    fi
    
    echo  # Add spacing between scripts
}

# Main testing function
main() {
    echo -e "${CYAN}=== CORE SERVICES SCRIPT TESTING SUITE ===${NC}"
    echo "Starting comprehensive script validation..."
    echo
    
    # Initialize
    initialize_test_environment
    
    # Test system dependencies
    test_dependencies
    
    # Test configuration files
    test_configuration
    
    # Test documentation
    test_documentation
    
    # Test all scripts
    log_info "Testing automation scripts..."
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        run_script_tests "$script"
    done
    
    # Generate reports
    generate_test_report
    
    # Final summary
    echo
    echo -e "${CYAN}=== TEST SUMMARY ===${NC}"
    echo -e "Total Tests: ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo
    
    local success_rate=0
    if [[ $TESTS_TOTAL -gt 0 ]]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    fi
    
    echo -e "Success Rate: ${BLUE}${success_rate}%${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ All tests passed! Scripts are ready for deployment.${NC}"
        log_info "Test suite completed successfully"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed. Please review and fix issues before deployment.${NC}"
        log_error "Test suite completed with failures"
        exit 1
    fi
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
            -q|--quick)
                QUICK_TEST=true
                shift
                ;;
            -s|--skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            -r|--no-report)
                GENERATE_REPORT=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi