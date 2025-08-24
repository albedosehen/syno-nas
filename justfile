default_cmd := "help"

help:
    @echo ""
    @echo "Synology NAS Configuration"
    @echo "========================================="
    @echo "Development:"
    @echo "  just fmt      - Run formatters against the project"
    @echo "  just check    - Run checkers against the project"
    @echo "  just lint     - Run linters against the project"
    @echo ""
    @echo ""
    @echo "Environment:"
    @echo "  just setup  - Installs all necessary tools for this project"
    @echo ""
    @echo ""
    @echo "CI/CD:"
    @echo "  just ci       - Run CI pipeline locally"
    @echo ""

## DEVELOPMENT

## SYSTEM MGMT
