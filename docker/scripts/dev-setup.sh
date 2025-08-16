#!/bin/bash

# Synology NAS Docker Management - Development Environment Setup Script
# This script sets up a complete development environment for working with
# the Docker management project, including tools, dependencies, and configurations

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSITIONS_DIR="$PROJECT_ROOT/compositions"
ENV_FILE="$PROJECT_ROOT/.env"
DEV_TOOLS_DIR="$PROJECT_ROOT/.devtools"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Setup tracking
SETUP_STEPS=0
SETUP_COMPLETED=0
SETUP_FAILED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((SETUP_COMPLETED++))
    ((SETUP_STEPS++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((SETUP_FAILED++))
    ((SETUP_STEPS++))
}

log_step() {
    echo -e "${PURPLE}[SETUP]${NC} $1"
}

# Help function
show_help() {
    echo "Synology NAS Docker Management - Development Environment Setup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --tools                     Install development tools"
    echo "  --environment               Setup development environment"
    echo "  --git                       Configure Git settings"
    echo "  --docker                    Setup Docker development environment"
    echo "  --testing                   Install testing frameworks"
    echo "  --linting                   Install code linting tools"
    echo "  --formatting                Install code formatting tools"
    echo "  --ide                       Setup IDE/editor configurations"
    echo "  --hooks                     Install Git hooks"
    echo "  --docs                      Setup documentation tools"
    echo "  --minimal                   Minimal setup (essential tools only)"
    echo "  --full                      Full development setup (all tools)"
    echo "  --update                    Update existing development tools"
    echo "  --clean                     Clean development environment"
    echo "  --check                     Check development environment status"
    echo "  --verbose                   Enable verbose output"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --full                   Complete development environment setup"
    echo "  $0 --minimal                Essential tools only"
    echo "  $0 --tools --testing        Install tools and testing frameworks"
    echo "  $0 --check                  Check current setup status"
    echo "  $0 --clean                  Clean up development environment"
    echo ""
}

# Parse command line arguments
INSTALL_TOOLS=false
SETUP_ENVIRONMENT=false
CONFIGURE_GIT=false
SETUP_DOCKER=false
INSTALL_TESTING=false
INSTALL_LINTING=false
INSTALL_FORMATTING=false
SETUP_IDE=false
INSTALL_HOOKS=false
SETUP_DOCS=false
MINIMAL_SETUP=false
FULL_SETUP=false
UPDATE_TOOLS=false
CLEAN_ENVIRONMENT=false
CHECK_STATUS=false
VERBOSE=false

# Default to minimal setup if no options provided
if [ $# -eq 0 ]; then
    MINIMAL_SETUP=true
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --tools)
            INSTALL_TOOLS=true
            shift
            ;;
        --environment)
            SETUP_ENVIRONMENT=true
            shift
            ;;
        --git)
            CONFIGURE_GIT=true
            shift
            ;;
        --docker)
            SETUP_DOCKER=true
            shift
            ;;
        --testing)
            INSTALL_TESTING=true
            shift
            ;;
        --linting)
            INSTALL_LINTING=true
            shift
            ;;
        --formatting)
            INSTALL_FORMATTING=true
            shift
            ;;
        --ide)
            SETUP_IDE=true
            shift
            ;;
        --hooks)
            INSTALL_HOOKS=true
            shift
            ;;
        --docs)
            SETUP_DOCS=true
            shift
            ;;
        --minimal)
            MINIMAL_SETUP=true
            shift
            ;;
        --full)
            FULL_SETUP=true
            shift
            ;;
        --update)
            UPDATE_TOOLS=true
            shift
            ;;
        --clean)
            CLEAN_ENVIRONMENT=true
            shift
            ;;
        --check)
            CHECK_STATUS=true
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

# Set flags for full setup
if [ "$FULL_SETUP" = true ]; then
    INSTALL_TOOLS=true
    SETUP_ENVIRONMENT=true
    CONFIGURE_GIT=true
    SETUP_DOCKER=true
    INSTALL_TESTING=true
    INSTALL_LINTING=true
    INSTALL_FORMATTING=true
    SETUP_IDE=true
    INSTALL_HOOKS=true
    SETUP_DOCS=true
fi

# Set flags for minimal setup
if [ "$MINIMAL_SETUP" = true ]; then
    INSTALL_TOOLS=true
    SETUP_ENVIRONMENT=true
    SETUP_DOCKER=true
fi

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

# Check if we're on Synology
is_synology() {
    [ -d "/volume1" ] && [ -f "/etc/synoinfo.conf" ]
}

# Setup development directories
setup_dev_directories() {
    if [ "$SETUP_ENVIRONMENT" = false ]; then
        return 0
    fi
    
    log_step "Setting up development directories..."
    
    # Create development tools directory
    mkdir -p "$DEV_TOOLS_DIR"
    mkdir -p "$PROJECT_ROOT/.vscode"
    mkdir -p "$PROJECT_ROOT/tests"
    mkdir -p "$PROJECT_ROOT/docs/dev"
    mkdir -p "$PROJECT_ROOT/logs"
    
    # Create .gitignore for development files
    cat > "$PROJECT_ROOT/.gitignore" << 'EOF'
# Development Environment
.devtools/
.vscode/settings.json
logs/*.log
tests/results/
*.tmp
*.swp
*~

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# IDE files
.idea/
*.iml
.project
.classpath

# Environment files (keep examples)
.env
*/.env
!.env.example
!*/.env.example

# Backup files
*.backup
*.bak
EOF
    
    log_success "Development directories created"
}

# Install essential development tools
install_development_tools() {
    if [ "$INSTALL_TOOLS" = false ]; then
        return 0
    fi
    
    log_step "Installing development tools..."
    
    # Check for package manager
    if command_exists opkg; then
        # Synology package manager
        verbose_log "Using opkg package manager"
        
        # Update package lists
        opkg update >/dev/null 2>&1 || log_warning "Could not update opkg packages"
        
        # Install essential tools
        local tools=("git" "curl" "wget" "jq" "bc")
        
        for tool in "${tools[@]}"; do
            if ! command_exists "$tool"; then
                if opkg install "$tool" >/dev/null 2>&1; then
                    log_success "Installed $tool"
                else
                    log_warning "Could not install $tool via opkg"
                fi
            else
                verbose_log "$tool is already installed"
            fi
        done
        
    elif command_exists apt-get; then
        # Debian/Ubuntu package manager
        verbose_log "Using apt package manager"
        
        sudo apt-get update >/dev/null 2>&1
        
        local tools=("git" "curl" "wget" "jq" "bc" "yamllint" "shellcheck")
        
        for tool in "${tools[@]}"; do
            if ! command_exists "$tool"; then
                if sudo apt-get install -y "$tool" >/dev/null 2>&1; then
                    log_success "Installed $tool"
                else
                    log_warning "Could not install $tool via apt"
                fi
            else
                verbose_log "$tool is already installed"
            fi
        done
        
    else
        log_warning "No supported package manager found"
    fi
    
    # Install tools that don't require package managers
    
    # Install Docker Compose if not present
    if ! command_exists docker-compose; then
        log_info "Installing Docker Compose..."
        
        local compose_version="1.29.2"
        local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
        
        if curl -L "$compose_url" -o "$DEV_TOOLS_DIR/docker-compose" 2>/dev/null; then
            chmod +x "$DEV_TOOLS_DIR/docker-compose"
            ln -sf "$DEV_TOOLS_DIR/docker-compose" /usr/local/bin/docker-compose 2>/dev/null || true
            log_success "Installed Docker Compose"
        else
            log_warning "Could not install Docker Compose"
        fi
    fi
    
    log_success "Development tools installation completed"
}

# Configure Git settings
configure_git_environment() {
    if [ "$CONFIGURE_GIT" = false ]; then
        return 0
    fi
    
    log_step "Configuring Git environment..."
    
    if ! command_exists git; then
        log_error "Git is not installed"
        return 1
    fi
    
    # Check if Git is already configured
    local git_name=$(git config --global user.name 2>/dev/null || echo "")
    local git_email=$(git config --global user.email 2>/dev/null || echo "")
    
    if [ -z "$git_name" ] || [ -z "$git_email" ]; then
        log_info "Git user configuration not found"
        log_info "Please configure Git with your name and email:"
        echo "  git config --global user.name \"Your Name\""
        echo "  git config --global user.email \"your.email@example.com\""
    else
        log_success "Git is configured for $git_name <$git_email>"
    fi
    
    # Set useful Git configurations
    git config --global init.defaultBranch main 2>/dev/null || true
    git config --global pull.rebase false 2>/dev/null || true
    git config --global core.autocrlf input 2>/dev/null || true
    
    log_success "Git environment configured"
}

# Setup Docker development environment
setup_docker_environment() {
    if [ "$SETUP_DOCKER" = false ]; then
        return 0
    fi
    
    log_step "Setting up Docker development environment..."
    
    # Check Docker installation
    if ! command_exists docker; then
        log_error "Docker is not installed"
        return 1
    fi
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    # Check Docker Compose
    if ! command_exists docker-compose; then
        log_warning "Docker Compose is not installed"
    else
        log_success "Docker Compose is available"
    fi
    
    # Setup Docker development network
    local dev_network="syno-nas-dev"
    if ! docker network ls | grep -q "$dev_network"; then
        if docker network create "$dev_network" >/dev/null 2>&1; then
            log_success "Created development Docker network: $dev_network"
        else
            log_warning "Could not create development Docker network"
        fi
    else
        verbose_log "Development Docker network already exists"
    fi
    
    # Create Docker development alias file
    cat > "$DEV_TOOLS_DIR/docker-aliases.sh" << 'EOF'
#!/bin/bash
# Docker development aliases

# Container management
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'
alias dvol='docker volume ls'
alias dnet='docker network ls'

# Docker Compose shortcuts
alias dc='docker-compose'
alias dcu='docker-compose up'
alias dcd='docker-compose down'
alias dcl='docker-compose logs'
alias dcb='docker-compose build'
alias dcp='docker-compose pull'

# Development helpers
alias dcdev='docker-compose -f docker-compose.yml -f docker-compose.dev.yml'
alias dtest='docker-compose -f docker-compose.test.yml'

# Cleanup commands
alias dclean='docker system prune -f'
alias dcleana='docker system prune -af'
alias drmvol='docker volume prune -f'

# Project specific
alias syno-deploy='./docker/scripts/deploy-project.sh'
alias syno-test='./docker/scripts/test-deployment.sh'
alias syno-health='./docker/scripts/health-check.sh'
alias syno-backup='./docker/scripts/backup-all.sh'
alias syno-clean='./docker/scripts/cleanup.sh'
EOF
    
    log_success "Docker development environment configured"
}

# Install testing frameworks
install_testing_frameworks() {
    if [ "$INSTALL_TESTING" = false ]; then
        return 0
    fi
    
    log_step "Installing testing frameworks..."
    
    # Install BATS (Bash Automated Testing System)
    if ! command_exists bats; then
        log_info "Installing BATS testing framework..."
        
        local bats_repo="https://github.com/bats-core/bats-core.git"
        local bats_dir="$DEV_TOOLS_DIR/bats"
        
        if git clone "$bats_repo" "$bats_dir" >/dev/null 2>&1; then
            cd "$bats_dir"
            sudo ./install.sh /usr/local >/dev/null 2>&1 || true
            cd "$PROJECT_ROOT"
            log_success "Installed BATS testing framework"
        else
            log_warning "Could not install BATS testing framework"
        fi
    else
        verbose_log "BATS is already installed"
    fi
    
    # Create sample test file
    cat > "$PROJECT_ROOT/tests/test_basic.bats" << 'EOF'
#!/usr/bin/env bats

# Basic tests for Docker management scripts

@test "project structure exists" {
    [ -d "docker/scripts" ]
    [ -d "docker/compositions" ]
    [ -f ".env.example" ]
}

@test "scripts are executable" {
    [ -x "docker/scripts/deploy-project.sh" ]
    [ -x "docker/scripts/manage-services.sh" ]
    [ -x "docker/scripts/health-check.sh" ]
}

@test "docker is available" {
    command -v docker
    docker --version
}

@test "docker-compose is available" {
    command -v docker-compose
    docker-compose --version
}
EOF
    
    chmod +x "$PROJECT_ROOT/tests/test_basic.bats"
    
    log_success "Testing frameworks installed"
}

# Install linting tools
install_linting_tools() {
    if [ "$INSTALL_LINTING" = false ]; then
        return 0
    fi
    
    log_step "Installing linting tools..."
    
    # Install ShellCheck if available
    if ! command_exists shellcheck; then
        if command_exists apt-get; then
            sudo apt-get install -y shellcheck >/dev/null 2>&1 || log_warning "Could not install shellcheck"
        else
            log_warning "ShellCheck not available for this system"
        fi
    else
        log_success "ShellCheck is available"
    fi
    
    # Install yamllint if available
    if ! command_exists yamllint; then
        if command_exists pip3; then
            pip3 install yamllint >/dev/null 2>&1 || log_warning "Could not install yamllint"
        elif command_exists apt-get; then
            sudo apt-get install -y yamllint >/dev/null 2>&1 || log_warning "Could not install yamllint"
        else
            log_warning "yamllint not available for this system"
        fi
    else
        log_success "yamllint is available"
    fi
    
    # Create linting script
    cat > "$DEV_TOOLS_DIR/lint.sh" << 'EOF'
#!/bin/bash

# Linting script for the project

echo "Running linting checks..."

# Lint shell scripts
if command -v shellcheck >/dev/null 2>&1; then
    echo "Checking shell scripts with ShellCheck..."
    find . -name "*.sh" -type f -exec shellcheck {} \; || echo "ShellCheck found issues"
else
    echo "ShellCheck not available"
fi

# Lint YAML files
if command -v yamllint >/dev/null 2>&1; then
    echo "Checking YAML files with yamllint..."
    find . -name "*.yml" -o -name "*.yaml" -type f -exec yamllint {} \; || echo "yamllint found issues"
else
    echo "yamllint not available"
fi

echo "Linting completed"
EOF
    
    chmod +x "$DEV_TOOLS_DIR/lint.sh"
    
    log_success "Linting tools installed"
}

# Setup IDE/Editor configurations
setup_ide_configuration() {
    if [ "$SETUP_IDE" = false ]; then
        return 0
    fi
    
    log_step "Setting up IDE configurations..."
    
    # VS Code settings
    cat > "$PROJECT_ROOT/.vscode/settings.json" << 'EOF'
{
    "files.associations": {
        "*.sh": "shellscript",
        "Dockerfile*": "dockerfile",
        "docker-compose*.yml": "dockercompose"
    },
    "shellcheck.enable": true,
    "yaml.validate": true,
    "yaml.format.enable": true,
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "editor.rulers": [80, 120],
    "files.exclude": {
        "**/.devtools": true,
        "**/logs/*.log": true,
        "**/*.tmp": true
    }
}
EOF
    
    # VS Code extensions recommendations
    cat > "$PROJECT_ROOT/.vscode/extensions.json" << 'EOF'
{
    "recommendations": [
        "ms-azuretools.vscode-docker",
        "redhat.vscode-yaml",
        "timonwong.shellcheck",
        "foxundermoon.shell-format",
        "ms-vscode.vscode-json"
    ]
}
EOF
    
    # VS Code tasks
    cat > "$PROJECT_ROOT/.vscode/tasks.json" << 'EOF'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Deploy Project",
            "type": "shell",
            "command": "./docker/scripts/deploy-project.sh",
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always"
            }
        },
        {
            "label": "Test Deployment",
            "type": "shell",
            "command": "./docker/scripts/test-deployment.sh",
            "group": "test",
            "presentation": {
                "echo": true,
                "reveal": "always"
            }
        },
        {
            "label": "Health Check",
            "type": "shell",
            "command": "./docker/scripts/health-check.sh",
            "group": "test",
            "presentation": {
                "echo": true,
                "reveal": "always"
            }
        },
        {
            "label": "Validate Config",
            "type": "shell",
            "command": "./docker/scripts/validate-config.sh",
            "group": "test",
            "presentation": {
                "echo": true,
                "reveal": "always"
            }
        },
        {
            "label": "Lint Code",
            "type": "shell",
            "command": "./.devtools/lint.sh",
            "group": "test",
            "presentation": {
                "echo": true,
                "reveal": "always"
            }
        }
    ]
}
EOF
    
    log_success "IDE configurations created"
}

# Install Git hooks
install_git_hooks() {
    if [ "$INSTALL_HOOKS" = false ]; then
        return 0
    fi
    
    log_step "Installing Git hooks..."
    
    # Create pre-commit hook
    cat > "$PROJECT_ROOT/.git/hooks/pre-commit" << 'EOF'
#!/bin/bash

# Pre-commit hook for code quality checks

echo "Running pre-commit checks..."

# Check for shell script issues
if command -v shellcheck >/dev/null 2>&1; then
    echo "Checking shell scripts..."
    git diff --cached --name-only | grep '\.sh$' | xargs shellcheck || {
        echo "ShellCheck found issues. Please fix before committing."
        exit 1
    }
fi

# Check for YAML issues
if command -v yamllint >/dev/null 2>&1; then
    echo "Checking YAML files..."
    git diff --cached --name-only | grep -E '\.(yml|yaml)$' | xargs yamllint || {
        echo "yamllint found issues. Please fix before committing."
        exit 1
    }
fi

# Check for trailing whitespace
if git diff --cached --check; then
    echo "Whitespace check passed"
else
    echo "Found trailing whitespace. Please fix before committing."
    exit 1
fi

echo "Pre-commit checks passed"
EOF
    
    chmod +x "$PROJECT_ROOT/.git/hooks/pre-commit"
    
    log_success "Git hooks installed"
}

# Clean development environment
clean_development_environment() {
    if [ "$CLEAN_ENVIRONMENT" = false ]; then
        return 0
    fi
    
    log_step "Cleaning development environment..."
    
    # Remove development tools directory
    if [ -d "$DEV_TOOLS_DIR" ]; then
        rm -rf "$DEV_TOOLS_DIR"
        log_success "Removed development tools directory"
    fi
    
    # Remove development Docker network
    local dev_network="syno-nas-dev"
    if docker network ls | grep -q "$dev_network"; then
        docker network rm "$dev_network" >/dev/null 2>&1 || true
        log_success "Removed development Docker network"
    fi
    
    # Clean up test results
    if [ -d "$PROJECT_ROOT/tests/results" ]; then
        rm -rf "$PROJECT_ROOT/tests/results"
        log_success "Cleaned test results"
    fi
    
    # Clean up log files
    find "$PROJECT_ROOT/logs" -name "*.log" -delete 2>/dev/null || true
    
    log_success "Development environment cleaned"
}

# Check development environment status
check_development_status() {
    if [ "$CHECK_STATUS" = false ]; then
        return 0
    fi
    
    log_step "Checking development environment status..."
    
    echo ""
    echo "Development Environment Status:"
    echo "==============================="
    
    # Check essential tools
    echo ""
    echo "Essential Tools:"
    local tools=("git" "docker" "docker-compose" "curl" "jq")
    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            echo "  ✓ $tool ($(command -v "$tool"))"
        else
            echo "  ✗ $tool (not found)"
        fi
    done
    
    # Check development tools
    echo ""
    echo "Development Tools:"
    local dev_tools=("shellcheck" "yamllint" "bats")
    for tool in "${dev_tools[@]}"; do
        if command_exists "$tool"; then
            echo "  ✓ $tool ($(command -v "$tool"))"
        else
            echo "  ✗ $tool (not installed)"
        fi
    done
    
    # Check directories
    echo ""
    echo "Project Structure:"
    local dirs=("docker/scripts" "docker/compositions" "tests" "logs" ".vscode")
    for dir in "${dirs[@]}"; do
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            echo "  ✓ $dir"
        else
            echo "  ✗ $dir (missing)"
        fi
    done
    
    # Check key files
    echo ""
    echo "Key Files:"
    local files=(".env.example" "docker/scripts/deploy-project.sh" "docker/scripts/health-check.sh")
    for file in "${files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            echo "  ✓ $file"
        else
            echo "  ✗ $file (missing)"
        fi
    done
    
    # Check Git configuration
    echo ""
    echo "Git Configuration:"
    if command_exists git; then
        local git_name=$(git config --global user.name 2>/dev/null || echo "not set")
        local git_email=$(git config --global user.email 2>/dev/null || echo "not set")
        echo "  Name: $git_name"
        echo "  Email: $git_email"
    else
        echo "  Git not available"
    fi
    
    echo ""
}

# Display setup summary
show_setup_summary() {
    echo ""
    echo "========================================"
    echo "       Development Setup Summary"
    echo "========================================"
    echo ""
    
    echo "Setup Results:"
    echo "  Steps Completed: $SETUP_COMPLETED"
    echo "  Steps Failed: $SETUP_FAILED"
    echo "  Total Steps: $SETUP_STEPS"
    
    if [ $SETUP_STEPS -gt 0 ]; then
        local success_rate=$(( SETUP_COMPLETED * 100 / SETUP_STEPS ))
        echo "  Success Rate: ${success_rate}%"
    fi
    
    echo ""
    
    if [ $SETUP_FAILED -eq 0 ]; then
        log_success "Development environment setup completed successfully!"
    else
        log_warning "Development environment setup completed with some issues"
    fi
    
    echo ""
    echo "Quick Start Commands:"
    echo "  Source aliases: source .devtools/docker-aliases.sh"
    echo "  Run tests: bats tests/"
    echo "  Lint code: .devtools/lint.sh"
    echo "  Deploy project: syno-deploy"
    echo "  Check health: syno-health"
    echo ""
    
    echo "Next Steps:"
    echo "  1. Review any failed setup steps above"
    echo "  2. Configure Git with your name and email if needed"
    echo "  3. Install additional tools as required for your workflow"
    echo "  4. Test the development environment with a sample deployment"
    echo ""
}

# Main execution
main() {
    echo "========================================"
    echo "   Development Environment Setup"
    echo "========================================"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    # Handle special cases first
    if [ "$CHECK_STATUS" = true ]; then
        check_development_status
        exit 0
    fi
    
    if [ "$CLEAN_ENVIRONMENT" = true ]; then
        clean_development_environment
        exit 0
    fi
    
    # Perform setup steps
    setup_dev_directories
    install_development_tools
    configure_git_environment
    setup_docker_environment
    install_testing_frameworks
    install_linting_tools
    setup_ide_configuration
    install_git_hooks
    
    # Show summary
    show_setup_summary
}

# Error handling
trap 'log_error "Development setup script failed on line $LINENO"' ERR

# Execute main function
main "$@"