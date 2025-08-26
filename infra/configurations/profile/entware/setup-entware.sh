#!/bin/bash
# setup-entware-refactored.sh
# Entware (opkg) Setup for Synology DSM 7.2+

set -euo pipefail
IFS=$'\n\t'

#=============================================================================
# CONFIGURATION AND CONSTANTS
#=============================================================================

readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/entware-setup.log"
readonly TEMP_DIR="$(mktemp -d -t entware-setup.XXXXXX)"
readonly BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"

# Entware configuration
readonly ENTWARE_BASE_URL="https://bin.entware.net"
readonly INSTALLER_PATH="/installer/generic.sh"
readonly CHECKSUM_URL_SUFFIX="/installer/generic.sh.sha256"

# Default configuration (can be overridden by environment variables)
: "${ENTWARE_ARCH:=""}"
: "${ENTWARE_INSTALL_PATH:="/opt"}"
: "${ENTWARE_BACKUP_EXISTING:="true"}"
: "${ENTWARE_INSTALL_PACKAGES:="jq git git-http zsh ripgrep tree eza curl htop tmux ca-bundle"}"
: "${ENTWARE_CREATE_SCHEDULER_TASK:="true"}"
: "${ENTWARE_VERBOSE:="false"}"
: "${ENTWARE_DRY_RUN:="false"}"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

#=============================================================================
# LOGGING AND OUTPUT FUNCTIONS
#=============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$@"
    if [[ "${ENTWARE_VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*" >&2
    fi
}

log_warn() {
    log "WARN" "$@"
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_step() {
    log "STEP" "$@"
    echo -e "${CYAN}[*]${NC} $*" >&2
}

log_debug() {
    if [[ "${ENTWARE_VERBOSE}" == "true" ]]; then
        log "DEBUG" "$@"
        echo -e "${MAGENTA}[DEBUG]${NC} $*" >&2
    fi
}

progress_bar() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))
    
    printf "\r["
    printf "%${completed}s" | tr ' ' '='
    printf "%${remaining}s" | tr ' ' '-'
    printf "] %d%%" "$percentage"
    
    if [[ "$current" -eq "$total" ]]; then
        echo
    fi
}

#=============================================================================
# ERROR HANDLING AND CLEANUP
#=============================================================================

cleanup() {
    local exit_code=$?
    log_debug "Starting cleanup process..."
    
    if [[ -d "${TEMP_DIR}" ]]; then
        log_debug "Removing temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code: $exit_code"
        log_error "Check the log file for details: ${LOG_FILE}"
    fi
    
    exit $exit_code
}

rollback_installation() {
    log_warn "Rolling back installation..."
    
    # Restore backed up /opt if it exists
    local backup_dir
    backup_dir=$(find /opt.broken.* -maxdepth 0 -type d 2>/dev/null | sort -r | head -n1)
    
    if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
        log_step "Restoring backup from: $backup_dir"
        if [[ "${ENTWARE_DRY_RUN}" != "true" ]]; then
            rm -rf "${ENTWARE_INSTALL_PATH}"
            mv "$backup_dir" "${ENTWARE_INSTALL_PATH}"
            log_success "Backup restored successfully"
        else
            log_info "DRY RUN: Would restore backup from $backup_dir"
        fi
    else
        log_warn "No backup found to restore"
    fi
}

die() {
    log_error "$@"
    rollback_installation
    exit 1
}

trap cleanup EXIT
trap 'die "Script interrupted by user"' INT TERM

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

validate_root_privileges() {
    log_step "Checking root privileges..."
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Use 'sudo -i' to become root."
    fi
    log_success "Running with root privileges"
}

validate_system_requirements() {
    log_step "Validating system requirements..."
    
    # Check if we're running on a Synology system
    if [[ ! -f /etc/synoinfo.conf ]]; then
        log_warn "This script is designed for Synology systems. Proceeding anyway..."
    fi
    
    # Check required commands
    local required_commands=("wget" "sha256sum" "mktemp" "date")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            die "Required command not found: $cmd"
        fi
    done
    
    # Check available disk space (minimum 100MB)
    local available_space
    available_space=$(df "${ENTWARE_INSTALL_PATH%/*}" | awk 'NR==2 {print $4}')
    if [[ "$available_space" -lt 102400 ]]; then
        die "Insufficient disk space. At least 100MB required."
    fi
    
    log_success "System requirements validated"
}

validate_network_connectivity() {
    log_step "Checking network connectivity..."
    if ! wget --spider --quiet --timeout=10 "${ENTWARE_BASE_URL}" 2>/dev/null; then
        die "Cannot reach Entware servers. Please check your internet connection."
    fi
    log_success "Network connectivity confirmed"
}

#=============================================================================
# ARCHITECTURE DETECTION
#=============================================================================

detect_architecture() {
    log_step "Detecting system architecture..."
    
    if [[ -n "${ENTWARE_ARCH}" ]]; then
        log_info "Using manually specified architecture: ${ENTWARE_ARCH}"
        echo "${ENTWARE_ARCH}"
        return
    fi
    
    local arch
    arch=$(uname -m)
    local detected_arch
    
    case "$arch" in
        x86_64)
            detected_arch="x64-k3.2"
            ;;
        armv7l)
            detected_arch="armv7sf-k3.2"
            ;;
        aarch64)
            detected_arch="aarch64-k3.10"
            ;;
        armv5tel)
            detected_arch="armv5sf-k3.2"
            ;;
        *)
            die "Unsupported architecture: $arch. Supported: x86_64, armv7l, aarch64, armv5tel"
            ;;
    esac
    
    log_success "Detected architecture: $detected_arch (from $arch)"
    echo "$detected_arch"
}

#=============================================================================
# INSTALLATION FUNCTIONS
#=============================================================================

backup_existing_installation() {
    if [[ "${ENTWARE_BACKUP_EXISTING}" != "true" ]]; then
        log_info "Skipping backup (ENTWARE_BACKUP_EXISTING=false)"
        return
    fi
    
    log_step "Backing up existing installation..."
    
    if [[ -d "${ENTWARE_INSTALL_PATH}" ]]; then
        local backup_path="${ENTWARE_INSTALL_PATH}.broken.${BACKUP_SUFFIX}"
        log_info "Moving existing ${ENTWARE_INSTALL_PATH} to ${backup_path}"
        
        if [[ "${ENTWARE_DRY_RUN}" != "true" ]]; then
            mv "${ENTWARE_INSTALL_PATH}" "$backup_path"
            log_success "Backup created: $backup_path"
        else
            log_info "DRY RUN: Would move ${ENTWARE_INSTALL_PATH} to $backup_path"
        fi
    else
        log_info "No existing installation found to backup"
    fi
}

download_and_verify_installer() {
    local arch="$1"
    local installer_url="${ENTWARE_BASE_URL}/${arch}${INSTALLER_PATH}"
    local checksum_url="${ENTWARE_BASE_URL}/${arch}${CHECKSUM_URL_SUFFIX}"
    local installer_file="${TEMP_DIR}/generic.sh"
    local checksum_file="${TEMP_DIR}/generic.sh.sha256"
    
    log_step "Downloading Entware installer..."
    log_info "Installer URL: $installer_url"
    
    if [[ "${ENTWARE_DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would download installer from $installer_url"
        return
    fi
    
    # Download installer with progress bar
    if ! wget --progress=dot:giga -O "$installer_file" "$installer_url" 2>&1 | \
        grep -o '[0-9]*%' | sed 's/%//' | while read -r percent; do
            progress_bar "$percent" 100
        done; then
        die "Failed to download installer from: $installer_url"
    fi
    
    log_success "Installer downloaded successfully"
    
    # Download and verify checksum
    log_step "Downloading and verifying checksum..."
    if wget --quiet -O "$checksum_file" "$checksum_url" 2>/dev/null; then
        local expected_checksum
        expected_checksum=$(cut -d' ' -f1 "$checksum_file")
        local actual_checksum
        actual_checksum=$(sha256sum "$installer_file" | cut -d' ' -f1)
        
        if [[ "$expected_checksum" == "$actual_checksum" ]]; then
            log_success "Checksum verification passed"
        else
            die "Checksum verification failed! Expected: $expected_checksum, Got: $actual_checksum"
        fi
    else
        log_warn "Could not download checksum file. Proceeding without verification."
    fi
    
    # Make installer executable
    chmod +x "$installer_file"
    
    echo "$installer_file"
}

install_entware() {
    local installer_file="$1"
    
    log_step "Installing Entware..."
    
    if [[ "${ENTWARE_DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would execute installer: $installer_file"
        return
    fi
    
    # Set up secure temporary directory for installer
    local installer_temp_dir
    installer_temp_dir=$(mktemp -d -t entware-installer.XXXXXX)
    chmod 700 "$installer_temp_dir"
    
    # Run installer with proper error handling
    if ! bash "$installer_file" 2>&1 | tee -a "${LOG_FILE}"; then
        rm -rf "$installer_temp_dir"
        die "Entware installation failed"
    fi
    
    rm -rf "$installer_temp_dir"
    log_success "Entware installed successfully"
}

configure_environment() {
    log_step "Configuring environment PATH..."
    
    local profiles=(
        "/etc/profile"
        "/root/.profile"
    )
    
    # Add user profile if running via sudo
    if [[ -n "${SUDO_USER:-}" ]]; then
        profiles+=("/var/services/homes/${SUDO_USER}/.profile")
    fi
    
    local path_export='export PATH=/opt/bin:/opt/sbin:$PATH'
    
    for profile in "${profiles[@]}"; do
        if [[ -f "$profile" ]]; then
            if ! grep -q '/opt/bin' "$profile" 2>/dev/null; then
                log_info "Adding PATH to: $profile"
                if [[ "${ENTWARE_DRY_RUN}" != "true" ]]; then
                    echo "$path_export" >> "$profile"
                    log_success "PATH added to $profile"
                else
                    log_info "DRY RUN: Would add PATH to $profile"
                fi
            else
                log_info "PATH already configured in: $profile"
            fi
        else
            log_debug "Profile not found: $profile"
        fi
    done
    
    # Export PATH for current session
    export PATH=/opt/bin:/opt/sbin:$PATH
    log_success "Environment configured"
}

update_package_lists() {
    log_step "Updating package lists..."
    
    if [[ "${ENTWARE_DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would run 'opkg update'"
        return
    fi
    
    if ! /opt/bin/opkg update 2>&1 | tee -a "${LOG_FILE}"; then
        die "Failed to update package lists"
    fi
    
    log_success "Package lists updated"
}

install_default_packages() {
    if [[ -z "${ENTWARE_INSTALL_PACKAGES}" ]]; then
        log_info "No packages specified for installation"
        return
    fi
    
    log_step "Installing default packages: ${ENTWARE_INSTALL_PACKAGES}"
    
    if [[ "${ENTWARE_DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would install packages: ${ENTWARE_INSTALL_PACKAGES}"
        return
    fi
    
    # Install packages one by one to handle failures gracefully
    local packages_array
    read -ra packages_array <<< "$ENTWARE_INSTALL_PACKAGES"
    
    local installed_packages=()
    local failed_packages=()
    
    for package in "${packages_array[@]}"; do
        log_info "Installing package: $package"
        if /opt/bin/opkg install "$package" 2>&1 | tee -a "${LOG_FILE}"; then
            installed_packages+=("$package")
            log_success "Package installed: $package"
        else
            failed_packages+=("$package")
            log_warn "Failed to install package: $package"
        fi
    done
    
    if [[ ${#installed_packages[@]} -gt 0 ]]; then
        log_success "Successfully installed packages: ${installed_packages[*]}"
    fi
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_warn "Failed to install packages: ${failed_packages[*]}"
        log_warn "You can try installing them manually later with: opkg install <package>"
    fi
}

install_github_cli() {
    log_step "Installing GitHub CLI (gh)..."
    
    if [[ "${ENTWARE_DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would install GitHub CLI"
        return
    fi
    
    # Detect architecture for GitHub CLI
    local arch
    arch=$(uname -m)
    local gh_arch
    
    case "$arch" in
        x86_64)
            gh_arch="amd64"
            ;;
        aarch64)
            gh_arch="arm64"
            ;;
        armv7l)
            gh_arch="armv6"
            ;;
        *)
            log_warn "Unsupported architecture for GitHub CLI: $arch. Skipping installation."
            return
            ;;
    esac
    
    log_info "Installing GitHub CLI for architecture: $gh_arch"
    
    # Create temporary directory for GitHub CLI installation
    local gh_temp_dir
    gh_temp_dir=$(mktemp -d -t github-cli.XXXXXX)
    
    # Cleanup function for GitHub CLI installation
    local cleanup_gh() {
        if [[ -d "$gh_temp_dir" ]]; then
            rm -rf "$gh_temp_dir"
        fi
    }
    
    # Get latest GitHub CLI version
    log_info "Fetching latest GitHub CLI version..."
    local gh_version
    if ! gh_version=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | cut -d '"' -f 4 | sed 's/^v//'); then
        log_error "Failed to fetch latest GitHub CLI version"
        cleanup_gh
        return 1
    fi
    
    if [[ -z "$gh_version" ]]; then
        log_error "Could not determine GitHub CLI version"
        cleanup_gh
        return 1
    fi
    
    log_info "Latest GitHub CLI version: $gh_version"
    
    # Download GitHub CLI
    local gh_url="https://github.com/cli/cli/releases/download/v${gh_version}/gh_${gh_version}_linux_${gh_arch}.tar.gz"
    local gh_tarball="$gh_temp_dir/gh.tar.gz"
    
    log_info "Downloading GitHub CLI from: $gh_url"
    if ! wget -O "$gh_tarball" "$gh_url" 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Failed to download GitHub CLI"
        cleanup_gh
        return 1
    fi
    
    # Extract GitHub CLI
    log_info "Extracting GitHub CLI..."
    if ! tar -xzf "$gh_tarball" -C "$gh_temp_dir" 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Failed to extract GitHub CLI"
        cleanup_gh
        return 1
    fi
    
    # Find the extracted directory
    local gh_extracted_dir
    gh_extracted_dir=$(find "$gh_temp_dir" -name "gh_${gh_version}_linux_${gh_arch}" -type d | head -n1)
    
    if [[ ! -d "$gh_extracted_dir" ]]; then
        log_error "Could not find extracted GitHub CLI directory"
        cleanup_gh
        return 1
    fi
    
    # Install GitHub CLI binary
    local gh_binary="$gh_extracted_dir/bin/gh"
    if [[ ! -f "$gh_binary" ]]; then
        log_error "GitHub CLI binary not found in extracted archive"
        cleanup_gh
        return 1
    fi
    
    log_info "Installing GitHub CLI to /opt/bin/gh..."
    if ! cp "$gh_binary" /opt/bin/gh; then
        log_error "Failed to copy GitHub CLI binary to /opt/bin/"
        cleanup_gh
        return 1
    fi
    
    # Set executable permissions
    if ! chmod 755 /opt/bin/gh; then
        log_error "Failed to set executable permissions on GitHub CLI"
        cleanup_gh
        return 1
    fi
    
    # Verify installation
    if /opt/bin/gh --version &>/dev/null; then
        log_success "GitHub CLI installed successfully"
        local installed_version
        installed_version=$(/opt/bin/gh --version | head -n1 | awk '{print $3}')
        log_info "Installed GitHub CLI version: $installed_version"
    else
        log_error "GitHub CLI installation verification failed"
        cleanup_gh
        return 1
    fi
    
    cleanup_gh
    return 0
}

create_scheduler_task() {
    if [[ "${ENTWARE_CREATE_SCHEDULER_TASK}" != "true" ]]; then
        log_info "Skipping scheduler task creation (ENTWARE_CREATE_SCHEDULER_TASK=false)"
        return
    fi
    
    log_step "Creating DSM Task Scheduler entry for auto-start..."
    
    local task_name="Entware Startup"
    local startup_command="/opt/etc/init.d/rc.unslung start"
    
    if [[ "${ENTWARE_DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would create scheduler task: $task_name"
        return
    fi
    
    # Check if synoschedtask is available
    if ! command -v synoschedtask &> /dev/null; then
        log_warn "synoschedtask not available. Scheduler task not created."
        log_info "You may need to manually create a boot-up task to run: $startup_command"
        return
    fi
    
    # Check if task already exists
    if synoschedtask --enum all 2>/dev/null | grep -q "$task_name"; then
        log_info "Scheduler task already exists: $task_name"
    else
        if synoschedtask --add bootup "$task_name" root "$startup_command" 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "Scheduler task created: $task_name"
        else
            log_warn "Failed to create scheduler task. You may need to create it manually."
            log_info "Manual task command: $startup_command"
        fi
    fi
}

#=============================================================================
# VERIFICATION FUNCTIONS
#=============================================================================

verify_installation() {
    log_step "Verifying installation..."
    
    # Check if opkg is available and working
    if [[ ! -x "/opt/bin/opkg" ]]; then
        die "Installation verification failed: opkg not found or not executable"
    fi
    
    # Test opkg functionality
    if ! /opt/bin/opkg --version &>/dev/null; then
        die "Installation verification failed: opkg not working properly"
    fi
    
    # Check if basic directory structure exists
    local required_dirs=("/opt/bin" "/opt/sbin" "/opt/etc" "/opt/lib")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_warn "Expected directory not found: $dir"
        fi
    done
    
    log_success "Installation verification completed"
}

display_installation_summary() {
    log_step "Installation Summary"
    echo
    echo "========================================="
    echo "  Entware Installation Complete"
    echo "========================================="
    echo
    echo "Installation Path: ${ENTWARE_INSTALL_PATH}"
    echo "Architecture: $(detect_architecture)"
    echo "Log File: ${LOG_FILE}"
    echo
    echo "Verify your installation with these commands:"
    echo "  /opt/bin/opkg --version"
    
    if [[ -n "${ENTWARE_INSTALL_PACKAGES}" ]]; then
        echo
        echo "Verify installed packages:"
        local packages_array
        read -ra packages_array <<< "$ENTWARE_INSTALL_PACKAGES"
        for package in "${packages_array[@]}"; do
            if [[ -x "/opt/bin/$package" ]]; then
                echo "  /opt/bin/$package --version"
            fi
        done
    fi
    
    # Check for GitHub CLI
    if [[ -x "/opt/bin/gh" ]]; then
        echo
        echo "Verify GitHub CLI:"
        echo "  /opt/bin/gh --version"
    fi
    
    echo
    echo "To use Entware tools, either:"
    echo "  1. Log out and back in (for persistent PATH)"
    echo "  2. Run: export PATH=/opt/bin:/opt/sbin:\$PATH"
    echo
    echo "Package management:"
    echo "  opkg update          # Update package lists"
    echo "  opkg list            # List available packages"
    echo "  opkg install <pkg>   # Install a package"
    echo "  opkg remove <pkg>    # Remove a package"
    echo
}

#=============================================================================
# MAIN FUNCTION
#=============================================================================

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Entware (opkg) Setup for Synology DSM 7.2+

OPTIONS:
    -h, --help             Show this help message
    -v, --verbose          Enable verbose output
    -n, --dry-run          Show what would be done without making changes
    --arch ARCH            Force specific architecture (e.g., x64-k3.2)
    --no-backup            Skip backing up existing installation
    --no-packages          Skip installing default packages
    --no-scheduler         Skip creating DSM scheduler task
    --packages PACKAGES    Space-separated list of packages to install

ENVIRONMENT VARIABLES:
    ENTWARE_ARCH                   Force specific architecture
    ENTWARE_INSTALL_PATH           Installation path (default: /opt)
    ENTWARE_BACKUP_EXISTING        Backup existing installation (default: true)
    ENTWARE_INSTALL_PACKAGES       Packages to install (default: jq git ripgrep htop tmux ca-bundle git-http)
    ENTWARE_CREATE_SCHEDULER_TASK  Create DSM scheduler task (default: true)
    ENTWARE_VERBOSE                Enable verbose output (default: false)
    ENTWARE_DRY_RUN                Dry run mode (default: false)

EXAMPLES:
    # Basic installation
    sudo $SCRIPT_NAME

    # Dry run to see what would be done
    sudo $SCRIPT_NAME --dry-run

    # Verbose installation with custom packages
    sudo $SCRIPT_NAME --verbose --packages "git htop nano"

    # Force specific architecture
    sudo $SCRIPT_NAME --arch armv7sf-k3.2

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                ENTWARE_VERBOSE="true"
                shift
                ;;
            -n|--dry-run)
                ENTWARE_DRY_RUN="true"
                shift
                ;;
            --arch)
                if [[ -n "${2:-}" ]]; then
                    ENTWARE_ARCH="$2"
                    shift 2
                else
                    die "Error: --arch requires an argument"
                fi
                ;;
            --no-backup)
                ENTWARE_BACKUP_EXISTING="false"
                shift
                ;;
            --no-packages)
                ENTWARE_INSTALL_PACKAGES=""
                shift
                ;;
            --no-scheduler)
                ENTWARE_CREATE_SCHEDULER_TASK="false"
                shift
                ;;
            --packages)
                if [[ -n "${2:-}" ]]; then
                    ENTWARE_INSTALL_PACKAGES="$2"
                    shift 2
                else
                    die "Error: --packages requires an argument"
                fi
                ;;
            *)
                die "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

main() {
    # Initialize logging
    echo "Starting Entware setup at $(date)" > "${LOG_FILE}"
    
    log_step "Starting Entware installation process..."
    log_info "Script: $SCRIPT_NAME"
    log_info "Version: 2.0.0"
    log_info "Log file: $LOG_FILE"
    
    if [[ "${ENTWARE_DRY_RUN}" == "true" ]]; then
        log_warn "DRY RUN MODE: No actual changes will be made"
    fi
    
    # Pre-installation validation
    validate_root_privileges
    validate_system_requirements
    validate_network_connectivity
    
    # Architecture detection
    local arch
    arch=$(detect_architecture)
    
    # Installation process
    backup_existing_installation
    
    local installer_file
    installer_file=$(download_and_verify_installer "$arch")
    
    install_entware "$installer_file"
    configure_environment
    update_package_lists
    install_default_packages
    install_github_cli
    create_scheduler_task
    
    # Post-installation verification
    if [[ "${ENTWARE_DRY_RUN}" != "true" ]]; then
        verify_installation
    fi
    
    display_installation_summary
    log_success "Entware installation completed successfully!"
}

#=============================================================================
# SCRIPT ENTRY POINT
#=============================================================================

# Parse command line arguments
parse_arguments "$@"

# Run main function
main

exit 0