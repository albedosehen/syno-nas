# Core Services - Modular Architecture

This directory contains the core infrastructure services for the Synology NAS home lab, designed with a modular architecture for easy management and scaling.

## Architecture Overview

### Services

- **Doppler**: Centralized secrets management via keyvault
- **SurrealDB**: Multi-model database with Doppler-managed credentials
- **Portainer**: Container management UI with secure authentication

### Modular Design

- **External Scripts**: Complex startup logic moved to dedicated script files
- **Docker Profiles**: Logical grouping for selective service deployment
- **Keyvault Structure**: Organized secret storage for scalability

## Directory Structure

```plaintext
core/
├── docker-compose.yml              # Main orchestration (includes all)
├── docker-compose.base.yml         # Base infrastructure (networks, volumes)
├── docker-compose.secrets.yml      # Secrets management (Doppler)
├── docker-compose.database.yml     # Database services (SurrealDB)
├── docker-compose.management.yml   # Management UI (Portainer)
├── .env.template                   # Environment configuration template
└── scripts/                        # Modular scripts
    ├── deploy.sh                   # Deployment helper script
    ├── doppler-keyvault-init.sh    # Doppler keyvault initialization
    ├── surrealdb-start.sh          # SurrealDB startup with secrets
    └── portainer-start.sh          # Portainer startup with auth
```

## Modular File-Based Deployment

### Available Modules

| Module | Compose File | Services | Use Case |
|--------|--------------|----------|----------|
| `base` | base.yml | networks, volumes | Infrastructure only |
| `secrets` | secrets.yml | doppler | Secrets management |
| `database` | database.yml | surrealdb | Database services |
| `management` | management.yml | portainer | Container management |
| `all` | docker-compose.yml | everything | Complete stack |

### Usage Examples

#### Using Individual Files

```bash
# Deploy base infrastructure
docker compose -f docker-compose.base.yml up -d

# Deploy secrets management
docker compose -f docker-compose.base.yml -f docker-compose.secrets.yml up -d

# Deploy database stack
docker compose -f docker-compose.base.yml \
                -f docker-compose.secrets.yml \
                -f docker-compose.database.yml up -d

# Deploy everything
docker compose up -d  # Uses main file with includes
```

#### Using Helper Script

```bash
# Deploy specific modules
./scripts/deploy.sh base up
./scripts/deploy.sh secrets
./scripts/deploy.sh database logs
./scripts/deploy.sh management restart
./scripts/deploy.sh all down

# View logs
./scripts/deploy.sh database logs

# Check status
./scripts/deploy.sh all status
```

## Keyvault Structure

```plaintext
/keyvault/
├── portainer/
│   ├── admin_password
│   └── admin_username
├── surrealdb/
│   ├── user
│   ├── password
│   ├── namespace
│   └── database
└── shared/
    ├── webhook_url
    ├── api_base_url
    └── notification_email
```

## Quick Start

1. **Copy environment template:**

   ```bash
   cp .env.template .env
   ```

2. **Configure Doppler token in .env:**

   ```bash
   DOPPLER_TOKEN=dp.pt.your_token_here
   ```

3. **Set secrets in Doppler dashboard:**
   - `PORTAINER_ADMIN_PASSWORD`
   - `SURREALDB_PASSWORD`
   - `SURREALDB_USERNAME`
   - etc.

4. **Deploy core services:**

   ```bash
   docker compose --profile core up -d
   ```

## Adding New Services

### 1. Create Service Script

```bash
# Create new service startup script
cat > scripts/myservice-start.sh << 'EOF'
#!/bin/bash
while [ ! -f /keyvault/myservice/config ]; do
  echo "Waiting for MyService secrets..."
  sleep 2
done
exec /myservice --config /keyvault/myservice/config
EOF
```

### 2. Update Doppler Script

Add your service's secrets to `scripts/doppler-keyvault-init.sh`:

```bash
# MyService secrets
printf "%s" "${MYSERVICE_API_KEY}" > /keyvault/myservice/api_key
printf "%s" "${MYSERVICE_CONFIG}" > /keyvault/myservice/config
```

### 3. Add Service to Compose

```yaml
myservice:
  image: myservice:latest
  profiles: ["myservice", "core", "all"]
  depends_on:
    doppler:
      condition: service_healthy
  volumes:
    - syno_core_keyvault:/keyvault:ro
    - ./scripts:/scripts:ro
  command: ["/bin/bash", "/scripts/myservice-start.sh"]
```

## Maintenance

### View Logs by Profile

```bash
# All core services
docker compose --profile core logs -f

# Database only
docker compose --profile database logs -f surrealdb

# Secrets management
docker compose --profile secrets logs -f doppler
```

### Update Scripts

Scripts are mounted as read-only volumes, so changes take effect on container restart:

```bash
# Edit script
nano scripts/surrealdb-start.sh

# Restart affected service
docker compose restart surrealdb
```

### Scale Services

```bash
# Scale SurrealDB (if needed)
docker compose --profile database up -d --scale surrealdb=2
```

## Security Notes

- Scripts are mounted read-only for security
- Keyvault permissions are managed by Doppler service
- No secrets stored in compose file or environment
- Services wait for secrets before starting

## Monitoring

Each service includes health checks appropriate to their function:

- **Doppler**: Version check
- **SurrealDB**: Port connectivity
- **Portainer**: None (minimal image constraints)

## Troubleshooting

### Services Won't Start

1. Check Doppler service health: `docker compose ps doppler`
2. Verify secrets in keyvault: `docker exec syno-core-doppler ls -la /keyvault/`
3. Check service logs: `docker compose logs servicename`

### Adding Secrets

1. Add to Doppler dashboard
2. Update `scripts/doppler-keyvault-init.sh`
3. Restart doppler: `docker compose restart doppler`
4. Restart dependent services
