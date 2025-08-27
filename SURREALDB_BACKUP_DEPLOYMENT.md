# SurrealDB Rolling Backup Solution - Deployment Guide

## Overview

The SurrealDB rolling backup solution provides automated, validated, and secure backups for the syno-core infrastructure. This deployment guide covers the initial setup and configuration process.

**For comprehensive usage instructions, monitoring, and troubleshooting, see [SurrealDB Backup System User Guide](SURREALDB_BACKUP_GUIDE.md).**

### System Components

- **Rolling 2-file backup strategy** (nightly + weekly overwrite pattern)
- **Container-based scheduling** with Alpine Linux + cron
- **Doppler keyvault integration** for secure authentication
- **Comprehensive validation and compression pipeline**
- **Health monitoring and structured logging**
- **Manual restore utilities**

### Prerequisites

- Synology NAS with DSM 7.2+
- Docker and Docker Compose installed
- SurrealDB service running in syno-core stack
- Doppler keyvault service configured and operational
- Administrative access to create directories and set permissions

## Deployment Steps

### 1. Environment Configuration

```bash
# Navigate to syno-core directory
cd infra/docker/apps/syno-core

# Copy environment template (if not exists)
cp .env.template .env

# Edit .env file with your specific configuration
# Required backup-specific variables:
```

**Required Environment Variables**:

```bash
# Health monitoring port (external)
SURREALDB_BACKUP_HEALTH_PORT=8081

# Backup storage location on host
SURREALDB_BACKUP_PATH=/volume1/docker/backups/surrealdb

# Resource constraints
SURREALDB_BACKUP_MEMORY_LIMIT=256M

# User/Group IDs for file permissions
PUID=1000
PGID=1000

# Timezone configuration
TZ=UTC
```

### 2. Directory Setup

```bash
# Create backup directory with correct permissions
mkdir -p /volume1/docker/backups/surrealdb
chown 1000:1000 /volume1/docker/backups/surrealdb

# Create log directory (if not exists)
mkdir -p /volume1/docker/logs/surrealdb-backup
chown 1000:1000 /volume1/docker/logs/surrealdb-backup
```

### 3. Deploy Services

```bash
# Deploy the complete syno-core stack
docker-compose up -d

# Verify backup service specifically
docker-compose ps surrealdb-backup
```

### 4. Post-Deployment Validation

#### Verify Service Status

```bash
# Check all services are running
docker-compose ps

# Specifically check backup service
docker-compose ps surrealdb-backup

# Expected output: surrealdb-backup should show "Up" status
```

#### Test Health Endpoint

```bash
# Test health endpoint responsiveness
curl http://localhost:8081/health

# Expected response format:
# {"status":"healthy|degraded","last_backup":"timestamp"}
```

#### Verify Dependencies

```bash
# Check Doppler keyvault is accessible
docker exec core-surrealdb-backup ls -la /keyvault/surrealdb/

# Test SurrealDB connectivity
docker exec core-surrealdb-backup curl -f http://core-surrealdb:8000/health

# Verify cron daemon is running
docker exec core-surrealdb-backup ps aux | grep cron
```

#### View Initial Logs

```bash
# Check container startup logs
docker logs core-surrealdb-backup

# Monitor real-time logs during initial startup
docker logs -f core-surrealdb-backup
```

### 5. Test Backup Functionality

#### Manual Backup Test

```bash
# Trigger manual nightly backup test
docker exec core-surrealdb-backup /scripts/backup-nightly.sh

# Expected output: JSON log entries showing backup progress
```

#### Verify Backup Creation

```bash
# Check backup files were created
ls -lh /volume1/docker/backups/surrealdb/

# Expected files:
# nightly_backup.surql.gz (if manual test completed)
```

#### Validate Backup Integrity

```bash
# Verify backup file integrity without restoration
docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --verify

# Expected output: "Backup validation successful"
```

### 6. Schedule Verification

```bash
# Verify cron schedule is loaded
docker exec core-surrealdb-backup crontab -l

# Expected output:
# 0 2 * * * /scripts/backup-nightly.sh >> /logs/surrealdb-backup/backup.log 2>&1
# 0 3 * * 0 /scripts/backup-weekly.sh >> /logs/surrealdb-backup/backup.log 2>&1
```

## File Structure Created

```plaintext
infra/docker/
├── apps/syno-core/
│   ├── docker-compose.yml          # Main orchestration file (includes database)
│   ├── docker-compose.database.yml # Database services including backup
│   ├── .env.template               # Updated with backup variables
│   └── scripts/backup/
│       ├── backup-entrypoint.sh    # Container startup
│       ├── backup-utils.sh         # Shared utilities
│       ├── backup-nightly.sh       # Nightly backup
│       ├── backup-weekly.sh        # Weekly backup
│       ├── health-server.sh        # Health check HTTP server
│       ├── restore-backup.sh       # Manual restore utility
│       └── README.md               # Detailed documentation
│
├── modules/components/surrealdb-backup/
│   ├── Dockerfile                  # Alpine + SurrealDB CLI + cron
│   └── crontab                     # Cron schedule definition
│
└── modules/services/surrealdb-backup/
    ├── docker-compose.yml          # Standalone service definition
    └── .env.template               # Service-specific configuration
```

## Backup Schedule

- **Nightly**: Every day at 2:00 AM (`0 2 * * *`)
  - File: `/volume1/docker/backups/surrealdb/nightly_backup.surql.gz`
  - Overwrites daily

- **Weekly**: Every Sunday at 3:00 AM (`0 3 * * 0`)
  - File: `/volume1/docker/backups/surrealdb/weekly_backup.surql.gz`
  - Overwrites weekly

## Health Monitoring

### Endpoints

- **Health Check**: `http://localhost:8081/health`
- **Container Logs**: `docker logs core-surrealdb-backup`

### Log Files

- **Backup Logs**: `/volume1/docker/logs/surrealdb-backup/backup.log`
- **Health Status**: `/volume1/docker/logs/surrealdb-backup/health.log`
- **Cron Logs**: `/volume1/docker/logs/surrealdb-backup/cron.log`

## Manual Operations

### Restore from Backup

```bash
# Restore from nightly backup (interactive)
docker exec -it core-surrealdb-backup /scripts/restore-backup.sh nightly

# Restore from weekly backup (force, no confirmation)
docker exec core-surrealdb-backup /scripts/restore-backup.sh weekly --force

# Verify backup integrity only
docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --verify
```

### Manual Backup

```bash
# Trigger manual nightly backup
docker exec core-surrealdb-backup /scripts/backup-nightly.sh

# Trigger manual weekly backup
docker exec core-surrealdb-backup /scripts/backup-weekly.sh
```

## Security Features

- **Non-root execution**: Container runs as PUID=1000
- **Read-only keyvault**: Doppler secrets mounted read-only
- **Network isolation**: Internal syno-core-network only
- **Minimal exposure**: Only health check port exposed
- **No hardcoded credentials**: All authentication via Doppler

## Troubleshooting

### Common Issues

1. **Service won't start**

   ```bash
   # Check dependencies
   docker-compose logs doppler
   docker-compose logs surrealdb
   
   # Check volume permissions
   ls -la /volume1/docker/backups/surrealdb/
   ```

2. **Backup fails**

   ```bash
   # Check SurrealDB connectivity
   docker exec core-surrealdb-backup curl -f http://core-surrealdb:8000/health
   
   # Check Doppler keyvault
   docker exec core-surrealdb-backup ls -la /keyvault/surrealdb/
   
   # View detailed logs
   docker exec core-surrealdb-backup tail -f /logs/surrealdb-backup/backup.log
   ```

3. **Health check fails**

   ```bash
   # Check health server process
   docker exec core-surrealdb-backup ps aux | grep health-server
   
   # Test health endpoint internally
   docker exec core-surrealdb-backup curl -f http://localhost:8080/health
   ```

## Maintenance

### Regular Tasks

- **Weekly**: Monitor backup logs and file sizes
- **Monthly**: Test restore procedures
- **Quarterly**: Verify backup integrity and update SurrealDB CLI

### Backup File Management

- **Nightly backup**: Rotates daily (always latest 24-hour snapshot)
- **Weekly backup**: Rotates weekly (always latest weekly snapshot)
- **Total storage**: Only 2 files maintained at any time

## Integration Points

### Doppler Keyvault

Required secrets in `/keyvault/surrealdb/`:

- `username` - SurrealDB root username
- `password` - SurrealDB root password
- `namespace` - Target namespace (default: core)
- `database` - Target database (default: services)

### Docker Compose Integration

The backup service is integrated into the main syno-core stack with proper dependencies:

- Depends on: `doppler`, `surrealdb`
- Network: `syno-core-network`
- Volumes: Shared keyvault, logs, and backup destinations

## Deployment Validation Checklist

Use this checklist to verify successful deployment:

- [ ] **Environment Configuration**: All required variables set in `.env`
- [ ] **Directory Setup**: Backup and log directories created with correct permissions
- [ ] **Service Deployment**: `core-surrealdb-backup` container running and healthy
- [ ] **Health Endpoint**: `http://localhost:8081/health` responds with 200 OK
- [ ] **Keyvault Access**: Doppler secrets accessible in container
- [ ] **SurrealDB Connectivity**: Backup service can connect to SurrealDB
- [ ] **Cron Schedule**: Backup schedules loaded and active
- [ ] **Manual Test**: Test backup completes successfully
- [ ] **Backup Validation**: Backup integrity verification passes
- [ ] **Log Generation**: Structured logs created in expected locations

## Next Steps

Once deployment is complete:

1. **Review the comprehensive [SurrealDB Backup System User Guide](SURREALDB_BACKUP_GUIDE.md)** for detailed usage instructions
2. **Set up monitoring** for the health endpoint and log files
3. **Schedule regular maintenance** tasks as outlined in the user guide
4. **Document any environment-specific configurations** for your team

## Related Documentation

- **[SurrealDB Backup System User Guide](SURREALDB_BACKUP_GUIDE.md)** - Complete usage, monitoring, and troubleshooting guide
- **[Backup Implementation Details](infra/docker/apps/syno-core/scripts/backup/README.md)** - Technical implementation documentation
- **[Docker Compose Configuration](infra/docker/apps/syno-core/docker-compose.yml)** - Service definition and dependencies
- **[Container Specification](infra/docker/modules/components/surrealdb-backup/Dockerfile)** - Container build details

---

**Deployment Guide Version**: 1.0
**Last Updated**: 2024
**Target Environment**: Synology NAS DSM 7.2+, Docker 20.10+
**Dependencies**: SurrealDB, Doppler keyvault, syno-core infrastructure
