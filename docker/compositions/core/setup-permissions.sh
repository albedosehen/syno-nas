#!/bin/bash
set -euo pipefail

# ===========================================
# SETUP SCRIPT PERMISSIONS
# ===========================================
# Ensures all scripts have proper executable permissions
# Platform: Linux/Synology DSM 7.2+
#
# Usage: ./setup-permissions.sh
# Author: Synology NAS Core Services Team
# Version: 1.0.0

# Color output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

echo -e "${GREEN}Setting up script permissions for Core Services...${NC}"
echo

# Scripts that need executable permissions
SCRIPTS=(
    "deploy.sh"
    "stop.sh"
    "backup.sh"
    "logs.sh"
    "status.sh"
    "update.sh"
    "test-scripts.sh"
    "setup-permissions.sh"
)

cd "$SCRIPT_DIR"

echo "Setting executable permissions for scripts:"
for script in "${SCRIPTS[@]}"; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        echo -e "  ✅ ${script}"
    else
        echo -e "  ${YELLOW}⚠️  ${script} (not found)${NC}"
    fi
done

echo
echo -e "${GREEN}✅ Script permissions setup completed!${NC}"
echo
echo "You can now run:"
echo "  ./deploy.sh    - Deploy core services"
echo "  ./status.sh    - Check service status"
echo "  ./logs.sh      - View service logs"
echo "  ./backup.sh    - Create backups"
echo "  ./update.sh    - Update services"
echo "  ./stop.sh      - Stop services"
echo "  ./test-scripts.sh - Test all scripts"
echo