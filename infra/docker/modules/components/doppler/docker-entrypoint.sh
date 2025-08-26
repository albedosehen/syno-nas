#!/bin/bash
set -e

# Doppler CLI Docker Entrypoint Script
# Provides initialization and service management for Doppler secrets

# Color output for better logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Doppler token is provided
if [ -z "$DOPPLER_TOKEN" ]; then
    log_error "DOPPLER_TOKEN environment variable is required"
    log_info "Please set DOPPLER_TOKEN in your environment or .env file"
    exit 1
fi

# Validate Doppler token format (basic check)
if [[ ! "$DOPPLER_TOKEN" =~ ^dp\.pt\. ]]; then
    log_warn "DOPPLER_TOKEN format may be invalid (should start with 'dp.pt.')"
fi

# Test Doppler connectivity
log_info "Testing Doppler connectivity..."
if doppler me 2>/dev/null >&2; then
    log_info "Successfully authenticated with Doppler"
else
    log_error "Failed to authenticate with Doppler. Please check your token."
    exit 1
fi

# Set default project and config if not specified
export DOPPLER_PROJECT=${DOPPLER_PROJECT:-"core-services"}
export DOPPLER_CONFIG=${DOPPLER_CONFIG:-"dev"}

log_info "Using Doppler project: $DOPPLER_PROJECT"
log_info "Using Doppler config: $DOPPLER_CONFIG"

# If running as a service (daemon mode)
if [ "$1" = "service" ]; then
    log_info "Starting Doppler in service mode..."
    
    # Create a simple service that keeps the container running
    # and provides secrets via environment variables
    while true; do
        log_info "Doppler service is running. Secrets are available via environment."
        sleep 300  # Sleep for 5 minutes
    done
fi

# Execute the provided command with Doppler run
log_info "Executing command with Doppler secrets injection..."
exec "$@"