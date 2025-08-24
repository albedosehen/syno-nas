# Doppler Configuration Guide for Core Services

A comprehensive guide for setting up and managing Doppler secrets management for the unified core services stack on Synology NAS DS1520+.

## Overview

Doppler serves as the centralized secrets management solution for the unified core services stack, providing:

- **Encrypted secret storage** with enterprise-grade security
- **Environment-based configuration** for development, staging, and production
- **Automatic secret injection** into Docker containers
- **Audit logging** for all secret access and modifications
- **Team collaboration** with granular access controls
- **Secret versioning** and rollback capabilities

### Architecture Integration

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    Doppler      │───▶│   Portainer     │    │   SurrealDB     │
│  (Secrets Mgmt) │    │ (Container Mgmt)│    │   (Database)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │  Core Network   │
                    │ (172.20.0.0/16) │
                    └─────────────────┘
```

## Prerequisites

### System Requirements

- **Doppler Account**: Free or paid account at [doppler.com](https://doppler.com)
- **Internet Access**: Required for Doppler API communication
- **Docker Environment**: Functional Docker and Docker Compose setup
- **Network Access**: Outbound HTTPS (443) access for Doppler API

### Required Permissions

- **Synology Admin**: Administrative access to Synology NAS
- **Docker Management**: Ability to manage Docker containers
- **File System**: Read/write access to `/volume1/docker/core/`

### Knowledge Prerequisites

- Basic understanding of environment variables
- Familiarity with Docker Compose
- Basic command-line interface skills

## Initial Setup

### Step 1: Create Doppler Account

1. **Sign up** at [doppler.com](https://doppler.com)
2. **Verify** your email address
3. **Complete** the onboarding process
4. **Choose** appropriate plan (Community plan sufficient for personal use)

### Step 2: Install Doppler CLI (Optional)

While not required for container operation, the CLI is useful for setup and management:

```bash
# On Synology NAS (if supported)
sudo curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://github.com/DopplerHQ/cli/releases/latest/download/doppler_linux_amd64.tar.gz | sudo tar -xzO doppler > /usr/local/bin/doppler && sudo chmod +x /usr/local/bin/doppler

# Verify installation
doppler --version
```

**Alternative**: Use the web dashboard exclusively (recommended for beginners).

### Step 3: Initial Authentication

```bash
# Login to Doppler (opens browser)
doppler login

# Verify authentication
doppler me
```

## Project Configuration

### Step 1: Create Core Services Project

#### Via CLI

```bash
# Create the project
doppler projects create core-services

# Set description
doppler projects update core-services --description "Unified core services for Synology NAS"
```

#### Via Web Dashboard

1. Navigate to [Doppler Dashboard](https://dashboard.doppler.com)
2. Click **"Create Project"**
3. Enter project details:
   - **Name**: `core-services`
   - **Description**: `Unified core services for Synology NAS`
4. Click **"Create Project"**

### Step 2: Create Environment Configurations

Create separate configurations for different deployment environments:

#### Development Configuration

```bash
# Create dev config
doppler configs create dev --project core-services --description "Development environment"

# Set as default for local development
doppler setup --project core-services --config dev
```

#### Production Configuration

```bash
# Create prod config
doppler configs create prod --project core-services --description "Production environment"
```

#### Staging Configuration (Optional)

```bash
# Create staging config
doppler configs create staging --project core-services --description "Staging environment"
```

### Step 3: Configure Environment Hierarchy

Set up inheritance between environments to minimize duplication:

1. **Base Configuration** (dev): Contains common settings
2. **Production Overrides**: Production-specific values
3. **Staging Overrides**: Staging-specific values

## Service Token Management

### Understanding Token Types

Doppler provides different token types for various use cases:

| Token Type | Use Case | Scope | Security Level |
|------------|----------|-------|----------------|
| **Service Token** | Production deployments | Single config | High |
| **CLI Token** | Development & management | User-based | Medium |
| **SCIM Token** | User provisioning | Organization | High |

### Creating Service Tokens

#### For Production Environment

1. **Navigate** to project: `core-services` → `prod` config
2. **Access** tab: Click "Access" in the top navigation
3. **Service Tokens** section: Click "Generate"
4. **Configure token**:
   - **Name**: `core-services-prod-token`
   - **Expires**: Set appropriate expiration (recommended: 1 year)
   - **Access**: Read-only (sufficient for container deployment)
5. **Copy token**: Securely store the token (format: `dp.pt.xxxxxxxxx`)

#### For Development Environment

```bash
# Generate service token via CLI
doppler configs tokens create core-services-dev-token \
    --project core-services \
    --config dev \
    --access read
```

### Token Security Best Practices

#### Do

- **Rotate tokens** regularly (quarterly recommended)
- **Use read-only** tokens for production deployments
- **Set expiration dates** for all tokens
- **Store tokens securely** (never in version control)
- **Monitor token usage** via audit logs
- **Use separate tokens** for different environments

#### Don't

- **Commit tokens** to version control
- **Share tokens** between environments
- **Use overly permissive** token scopes
- **Store tokens** in plain text files
- **Use CLI tokens** in production

## Environment Configuration

### Core Service Secrets

Configure essential secrets for all core services:

#### Database Configuration

```bash
# SurrealDB credentials
doppler secrets set SURREALDB_USER admin --project core-services --config dev
doppler secrets set SURREALDB_PASS "$(openssl rand -base64 32)" --project core-services --config dev
doppler secrets set SURREALDB_NAMESPACE core --project core-services --config dev
doppler secrets set SURREALDB_DATABASE services --project core-services --config dev

# Database connection settings
doppler secrets set DB_HOST core-surrealdb --project core-services --config dev
doppler secrets set DB_PORT 8000 --project core-services --config dev
```

#### API Keys and External Services

```bash
# Example external API configurations
doppler secrets set WEBHOOK_SECRET "$(openssl rand -hex 32)" --project core-services --config dev
doppler secrets set API_ENCRYPTION_KEY "$(openssl rand -base64 32)" --project core-services --config dev
doppler secrets set JWT_SECRET "$(openssl rand -base64 64)" --project core-services --config dev
```

#### Security Configuration

```bash
# SSL/TLS certificates (if using custom certs)
doppler secrets set SSL_CERT_PATH "/certs/server.crt" --project core-services --config dev
doppler secrets set SSL_KEY_PATH "/certs/server.key" --project core-services --config dev

# Security headers
doppler secrets set SECURITY_HEADERS_ENABLED true --project core-services --config dev
doppler secrets set RATE_LIMITING_ENABLED true --project core-services --config dev
```

### Environment-Specific Configuration

#### Development Settings

```bash
# Development-specific configurations
doppler secrets set LOG_LEVEL DEBUG --project core-services --config dev
doppler secrets set DEV_MODE true --project core-services --config dev
doppler secrets set ENABLE_DEBUG_FEATURES true --project core-services --config dev
doppler secrets set AUTO_MIGRATION true --project core-services --config dev
```

#### Production Settings

```bash
# Production-specific configurations
doppler secrets set LOG_LEVEL INFO --project core-services --config prod
doppler secrets set DEV_MODE false --project core-services --config prod
doppler secrets set ENABLE_DEBUG_FEATURES false --project core-services --config prod
doppler secrets set AUTO_MIGRATION false --project core-services --config prod

# Production security
doppler secrets set SECURITY_HEADERS_ENABLED true --project core-services --config prod
doppler secrets set RATE_LIMITING_ENABLED true --project core-services --config prod
doppler secrets set AUDIT_LOGGING_ENABLED true --project core-services --config prod
```

### Secret Organization

Organize secrets using consistent naming conventions:

#### Naming Convention

```text
{SERVICE}_{COMPONENT}_{PURPOSE}
```

#### Examples

- `SURREALDB_AUTH_PASSWORD`
- `PORTAINER_API_KEY`
- `BACKUP_ENCRYPTION_PASSPHRASE`
- `WEBHOOK_SIGNING_SECRET`

## 🔒 Security Best Practices

### Access Control

#### Team Member Management

1. **Invite team members** with appropriate roles:
   - **Admin**: Full project access
   - **Developer**: Read/write access to dev configs
   - **Viewer**: Read-only access for monitoring

2. **Configure role-based access**:

   ```bash
   # Invite team member with developer role
   doppler team add user@example.com --role developer
   ```

#### Environment Isolation

- **Separate tokens** for each environment
- **Restricted access** to production configs
- **Audit trails** for all secret modifications

### Secret Rotation Strategy

#### Automated Rotation Schedule

- **Database passwords**: Quarterly
- **API keys**: Bi-annually  
- **Service tokens**: Annually
- **Encryption keys**: On security incident

#### Manual Rotation Process

1. **Generate new secret** in Doppler
2. **Update dependent services** gracefully
3. **Verify functionality** with new secret
4. **Revoke old secret** after confirmation
5. **Document rotation** in audit log

### Encryption and Storage

#### Secret Encryption

- **AES-256-GCM** encryption at rest
- **TLS 1.2+** for data in transit
- **Zero-knowledge architecture** (Doppler cannot see plaintext)

#### Local Security

- **File permissions**: Restrict access to service account only
- **Memory protection**: Secrets loaded directly into container memory
- **No disk storage**: Avoid writing secrets to disk

## Production Configurations

### Production-Ready Setup

#### Environment Configurations

```bash
# Production service token setup
export DOPPLER_TOKEN="dp.pt.your-production-token-here"
export DOPPLER_PROJECT="core-services"
export DOPPLER_CONFIG="prod"

# Verify production configuration
doppler secrets --project core-services --config prod
```

#### Production Secrets Checklist

- [ ] **Database credentials** with strong passwords
- [ ] **API keys** for external services
- [ ] **SSL certificates** for HTTPS
- [ ] **Encryption keys** for sensitive data
- [ ] **Backup encryption** passphrases
- [ ] **Monitoring tokens** for alerting systems
- [ ] **Webhook secrets** for integrations

#### Security Hardening

```bash
# Production security settings
doppler secrets set FORCE_SSL true --project core-services --config prod
doppler secrets set SECURE_COOKIES true --project core-services --config prod
doppler secrets set SESSION_TIMEOUT 3600 --project core-services --config prod
doppler secrets set MAX_LOGIN_ATTEMPTS 5 --project core-services --config prod
```

### Monitoring and Alerting

#### Audit Log Monitoring

1. **Enable audit logs** in Doppler dashboard
2. **Configure alerts** for:
   - Secret modifications
   - Token usage anomalies
   - Failed authentication attempts
   - Unusual access patterns

#### Health Check Integration

```bash
# Health check endpoints with secrets
doppler secrets set HEALTH_CHECK_TOKEN "$(openssl rand -hex 16)" --project core-services --config prod
doppler secrets set MONITORING_API_KEY "your-monitoring-api-key" --project core-services --config prod
```

## Development Configurations

### Development Environment Setup

#### Local Development

```bash
# Set up local development environment
doppler setup --project core-services --config dev

# View all development secrets
doppler secrets --project core-services --config dev

# Run services with Doppler injection
doppler run -- docker-compose up -d
```

#### Development-Specific Secrets

```bash
# Development database (can use weaker passwords)
doppler secrets set SURREALDB_PASS "dev_password_123" --project core-services --config dev

# Development API keys (often test/sandbox keys)
doppler secrets set STRIPE_API_KEY "sk_test_..." --project core-services --config dev
doppler secrets set SENDGRID_API_KEY "SG.test..." --project core-services --config dev

# Debug and testing
doppler secrets set DEBUG_ENABLED true --project core-services --config dev
doppler secrets set TEST_DATA_ENABLED true --project core-services --config dev
```

### Local Override Configuration

For local development overrides:

```bash
# Create local override file (not committed to VCS)
cat > .env.local << EOF
# Local development overrides
SURREALDB_PORT=8002
PORTAINER_PORT=9001
DEBUG_VERBOSE=true
EOF

# Use with Docker Compose
doppler run -- docker-compose --env-file .env.local up -d
```

## Core Services

### Docker Compose Integration

#### Updated docker-compose.yml

```yaml
services:
  doppler:
    build:
      context: ./doppler
      dockerfile: Dockerfile
    image: synology-nas/doppler-alpine:latest
    container_name: core-doppler
    restart: unless-stopped
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-UTC}
      - DOPPLER_TOKEN=${DOPPLER_TOKEN}
      - DOPPLER_PROJECT=${DOPPLER_PROJECT:-core-services}
      - DOPPLER_CONFIG=${DOPPLER_CONFIG:-dev}
    healthcheck:
      test: ["CMD", "doppler", "--version"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
    networks:
      - core-network
    command: ["service"]

  surrealdb:
    image: surrealdb/surrealdb:latest
    container_name: core-surrealdb
    restart: unless-stopped
    depends_on:
      doppler:
        condition: service_healthy
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-UTC}
    command: 
      - start
      - --bind
      - "0.0.0.0:8000"
      - --user
      - "${SURREALDB_USER:-admin}"
      - --pass
      - "${SURREALDB_PASS:-}"
      - file:/data/database.db
    networks:
      - core-network
```

### Environment Variable Mapping

#### Doppler to Service Mapping

```bash
# Map Doppler secrets to container environment variables
doppler secrets set CONTAINER_SURREALDB_USER admin --project core-services --config dev
doppler secrets set CONTAINER_SURREALDB_PASS "secure_password" --project core-services --config dev
doppler secrets set CONTAINER_PORTAINER_ADMIN_PASSWORD "admin_password" --project core-services --config dev
```

#### Service-Specific Configuration

**SurrealDB Integration:**

```bash
# Database configuration
doppler secrets set SURREALDB_USER admin
doppler secrets set SURREALDB_PASS "$(openssl rand -base64 32)"
doppler secrets set SURREALDB_NAMESPACE core
doppler secrets set SURREALDB_DATABASE services
doppler secrets set SURREALDB_LOG_LEVEL info
```

**Portainer Integration:**

```bash
# Portainer configuration
doppler secrets set PORTAINER_ADMIN_PASSWORD "$(openssl rand -base64 24)"
doppler secrets set PORTAINER_SECRET_KEY "$(openssl rand -hex 32)"
```

### Automated Secret Injection

#### Deployment Script Integration

```bash
#!/bin/bash
# Enhanced deployment with Doppler integration

# Verify Doppler authentication
if ! doppler me &>/dev/null; then
    echo "Error: Doppler authentication required"
    exit 1
fi

# Inject secrets and deploy
echo "Deploying with Doppler secrets injection..."
doppler run --project core-services --config prod -- docker-compose up -d

# Verify deployment
doppler run --project core-services --config prod -- ./status.sh
```

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: Authentication Failed

```bash
# Symptom: "Authentication failed" in Doppler container logs
# Cause: Invalid or expired service token

# Solution:
# 1. Verify token format
echo $DOPPLER_TOKEN | grep "^dp\.pt\."

# 2. Test token validity
doppler me --token "$DOPPLER_TOKEN"

# 3. Regenerate token if needed
doppler configs tokens create new-token --project core-services --config dev
```

#### Issue 2: Secret Not Found

```bash
# Symptom: Environment variable empty in container
# Cause: Secret not defined in current config

# Solution:
# 1. List all secrets in config
doppler secrets --project core-services --config dev

# 2. Add missing secret
doppler secrets set MISSING_SECRET "value" --project core-services --config dev

# 3. Restart container to pick up change
docker-compose restart service-name
```

#### Issue 3: Network Connectivity

```bash
# Symptom: Cannot connect to Doppler API
# Cause: Network restrictions or DNS issues

# Solution:
# 1. Test connectivity
curl -I https://api.doppler.com

# 2. Check DNS resolution
nslookup api.doppler.com

# 3. Verify firewall rules
# Ensure outbound HTTPS (443) is allowed
```

#### Issue 4: Container Startup Failure

```bash
# Symptom: Doppler container exits immediately
# Cause: Missing required environment variables

# Solution:
# 1. Check container logs
docker logs core-doppler

# 2. Verify environment variables
docker exec core-doppler printenv | grep DOPPLER

# 3. Validate .env file
grep DOPPLER .env
```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Enable debug logging in Doppler container
export DOPPLER_LOG_LEVEL=debug

# Run with debug output
doppler run --debug -- docker-compose up -d

# Check detailed logs
docker logs core-doppler --follow
```

### Validation Scripts

#### Secret Validation

```bash
#!/bin/bash
# validate-secrets.sh

echo "Validating Doppler secrets configuration..."

# Check required secrets exist
REQUIRED_SECRETS=(
    "SURREALDB_USER"
    "SURREALDB_PASS"
    "DOPPLER_TOKEN"
)

for secret in "${REQUIRED_SECRETS[@]}"; do
    if doppler secrets get "$secret" --project core-services --config dev &>/dev/null; then
        echo "✓ $secret: exists"
    else
        echo "✗ $secret: missing"
    fi
done

echo "Validation complete."
```

### Custom Secret Providers

#### Integration with External Vaults

```bash
# HashiCorp Vault integration
doppler secrets set VAULT_ADDR "https://vault.company.com"
doppler secrets set VAULT_TOKEN "hvs.your-vault-token"

# AWS Secrets Manager integration
doppler secrets set AWS_REGION "us-west-2"
doppler secrets set AWS_ACCESS_KEY_ID "your-access-key"
doppler secrets set AWS_SECRET_ACCESS_KEY "your-secret-key"
```

### Dynamic Secret Generation

#### Time-based Secrets

```bash
# Generate time-based rotation tokens
ROTATION_SECRET=$(date +%s | sha256sum | base64 | head -c 32)
doppler secrets set ROTATION_TOKEN "$ROTATION_SECRET" --project core-services --config prod
```

#### Template-based Configuration

```bash
# Use Doppler templates for complex configurations
doppler secrets set DATABASE_URL "postgres://{{SURREALDB_USER}}:{{SURREALDB_PASS}}@{{DB_HOST}}:{{DB_PORT}}/{{SURREALDB_DATABASE}}"
```

### API Integration

#### Programmatic Secret Management

```bash
# Get secrets via API
curl -H "Authorization: Bearer $DOPPLER_TOKEN" \
     "https://api.doppler.com/v3/configs/config/secrets?project=core-services&config=dev"

# Update secrets via API
curl -X POST \
     -H "Authorization: Bearer $DOPPLER_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"secrets": {"NEW_SECRET": "new_value"}}' \
     "https://api.doppler.com/v3/configs/config/secrets?project=core-services&config=dev"
```

## Backup and Recovery

### Doppler Configuration Backup

#### Export Current Configuration

```bash
# Export all secrets (excluding values for security)
doppler secrets download --project core-services --config dev --format json > secrets-backup.json

# Export configuration metadata
doppler configs get --project core-services --config dev --format json > config-backup.json
```

#### Backup Script

```bash
#!/bin/bash
# backup-doppler-config.sh

BACKUP_DIR="/volume1/docker/backups/core/doppler"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

mkdir -p "$BACKUP_PATH"

# Backup configurations
for config in dev staging prod; do
    if doppler configs get --project core-services --config "$config" &>/dev/null; then
        doppler secrets download \
            --project core-services \
            --config "$config" \
            --format env > "$BACKUP_PATH/secrets-$config.env"
    fi
done

echo "Doppler configuration backed up to: $BACKUP_PATH"
```

### Disaster Recovery

#### Recovery Process

1. **Create new Doppler project** if needed
2. **Restore configurations** from backup
3. **Generate new service tokens**
4. **Update deployment configurations**
5. **Verify secret injection** in containers

#### Recovery Script

```bash
#!/bin/bash
# restore-doppler-config.sh

BACKUP_PATH="$1"

if [[ ! -d "$BACKUP_PATH" ]]; then
    echo "Error: Backup path not found: $BACKUP_PATH"
    exit 1
fi

# Restore configurations
for env_file in "$BACKUP_PATH"/secrets-*.env; do
    config=$(basename "$env_file" .env | sed 's/secrets-//')
    echo "Restoring configuration: $config"
    
    doppler secrets upload "$env_file" \
        --project core-services \
        --config "$config"
done

echo "Doppler configuration restored successfully"
```

### Monitoring and Alerts

#### Set up monitoring for

- **Secret access patterns**
- **Token usage anomalies**
- **Configuration changes**
- **Failed authentication attempts**

#### Integration with monitoring systems

```bash
# Example: Send alerts to Slack
doppler secrets set SLACK_WEBHOOK_URL "https://hooks.slack.com/services/..." --project core-services --config prod
doppler secrets set ALERT_EMAIL "admin@company.com" --project core-services --config prod
```

---

## Additional Resources

### Documentation Links

- [Doppler Official Documentation](https://docs.doppler.com/)
- [Docker Compose Integration](https://docs.doppler.com/docs/docker-compose)
- [Security Best Practices](https://docs.doppler.com/docs/security)
- [API Reference](https://docs.doppler.com/reference)

### Community Resources

- [Doppler Community Forum](https://community.doppler.com/)
- [GitHub Examples](https://github.com/DopplerHQ/examples)
- [Video Tutorials](https://www.youtube.com/c/DopplerHQ)

### Support Channels

- **Documentation**: [docs.doppler.com](https://docs.doppler.com)
- **Community Support**: [community.doppler.com](https://community.doppler.com)
- **Enterprise Support**: Available with paid plans
- **Email Support**: <support@doppler.com>

---

**Version**: 1.0.0  
**Last Updated**: 2024  
**Compatible With**: Doppler CLI v3.x, Docker 20.10+, Synology DSM 7.2+

For project-specific support, see the main [README.md](./README.md) or open an issue in the project repository.
