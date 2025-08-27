# SurrealDB Backup System User Guide

## Overview

The SurrealDB backup system provides automated, validated, and secure backups for the syno-core infrastructure using a rolling 2-file strategy. This system ensures data protection with minimal storage overhead while maintaining comprehensive monitoring and recovery capabilities.

### System Architecture

- **Rolling Strategy**: Maintains exactly 2 backup files (`nightly_backup.surql.gz`, `weekly_backup.surql.gz`)
- **Automated Scheduling**: Container-based cron scheduling with staggered timing
- **Security Integration**: Doppler keyvault for credential management
- **Health Monitoring**: HTTP endpoint with structured logging
- **Validation Pipeline**: Export validation and integrity checks

### Key Features

- **Automated Backups**: Daily at 2:00 AM, Weekly on Sunday at 3:00 AM
- **Space Efficient**: Rolling overwrite pattern maintains only 2 files maximum
- **Comprehensive Validation**: Pre and post-backup integrity verification
- **Secure Authentication**: No hardcoded credentials, keyvault integration
- **Resource Constrained**: 256MB memory limit with non-root execution
- **Health Monitoring**: Real-time status via HTTP endpoint and structured logs

---

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Synology NAS with DSM 7.2+
- Doppler keyvault configured with SurrealDB credentials
- SurrealDB service running in syno-core stack

### Deploy Backup Service

```bash
# Navigate to syno-core directory
cd infra/docker/apps/syno-core

# Ensure environment is configured
cp .env.template .env
# Edit .env with your configuration

# Create backup directory
mkdir -p /volume1/docker/backups/surrealdb

# Deploy services
docker-compose up -d
```

### Verify Installation

```bash
# Check service status
docker-compose ps | grep backup

# Test health endpoint
curl http://localhost:8081/health

# Verify backup directory
ls -la /volume1/docker/backups/surrealdb/
```

---

## How-to Guides

### Monitor Backup Status

#### Check Service Health

```bash
# Quick health check
curl http://localhost:8081/health

# Expected response: {"status":"healthy","last_backup":"2024-01-01T02:00:00Z"}
```

#### View Backup Logs

```bash
# Real-time backup logs
docker logs -f core-surrealdb-backup

# Structured JSON logs
docker exec core-surrealdb-backup tail -f /logs/surrealdb-backup/backup.log

# Cron execution logs
docker exec core-surrealdb-backup tail -f /logs/surrealdb-backup/cron.log
```

#### Check Backup Files

```bash
# List backup files with sizes
ls -lh /volume1/docker/backups/surrealdb/

# Verify file integrity
docker exec core-surrealdb-backup gzip -t /backups/nightly_backup.surql.gz
docker exec core-surrealdb-backup gzip -t /backups/weekly_backup.surql.gz
```

### Manual Backup Operations

#### Trigger Manual Backup

```bash
# Run nightly backup immediately
docker exec core-surrealdb-backup /scripts/backup-nightly.sh

# Run weekly backup immediately
docker exec core-surrealdb-backup /scripts/backup-weekly.sh
```

#### Verify Backup Integrity

```bash
# Verify nightly backup without restoration
docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --verify

# Verify weekly backup without restoration
docker exec core-surrealdb-backup /scripts/restore-backup.sh weekly --verify
```

### Restore Data from Backup

> **Warning**: Data restoration will overwrite existing database content. Always verify backup integrity before proceeding.

#### Interactive Restoration

```bash
# Restore from nightly backup with confirmation prompts
docker exec -it core-surrealdb-backup /scripts/restore-backup.sh nightly

# Restore from weekly backup with confirmation prompts
docker exec -it core-surrealdb-backup /scripts/restore-backup.sh weekly
```

#### Automated Restoration

```bash
# Force restore from nightly backup (no prompts)
docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --force

# Force restore from weekly backup (no prompts)
docker exec core-surrealdb-backup /scripts/restore-backup.sh weekly --force
```

### Emergency Recovery Procedures

#### Complete Database Recovery

1. **Stop SurrealDB service**:

   ```bash
   docker stop core-surrealdb
   ```

2. **Clear corrupted database** (if necessary):

   ```bash
   # Backup existing data first
   mv /volume1/docker/core/surrealdb/data/database.db /volume1/docker/core/surrealdb/data/database.db.corrupted
   ```

3. **Restart SurrealDB service**:

   ```bash
   docker start core-surrealdb
   # Wait for service to be ready
   sleep 10
   ```

4. **Restore from backup**:

   ```bash
   # Use nightly for most recent data
   docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --force

   # Or use weekly for more stable data
   docker exec core-surrealdb-backup /scripts/restore-backup.sh weekly --force
   ```

5. **Verify restoration**:

   ```bash
   docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --verify
   ```

#### Service Recovery

```bash
# Restart backup service
docker restart core-surrealdb-backup

# Check service dependencies
docker-compose logs doppler-core
docker-compose logs surrealdb

# Verify keyvault access
docker exec core-surrealdb-backup ls -la /keyvault/surrealdb/
```

---

## Reference

### File Locations

#### Host System Paths

| Path | Purpose | Permissions |
|------|---------|-------------|
| `/volume1/docker/backups/surrealdb/` | Backup files storage | Read/Write (PUID=1000) |
| `/volume1/docker/logs/surrealdb-backup/` | Log files | Read/Write (PUID=1000) |
| [`infra/docker/apps/syno-core/scripts/backup/`](infra/docker/apps/syno-core/scripts/backup/) | Backup scripts | Read-only |

#### Container Paths

| Path | Purpose | Mount Type |
|------|---------|------------|
| `/backups/` | Backup file destination | Read/Write |
| `/logs/surrealdb-backup/` | Log file destination | Read/Write |
| `/keyvault/surrealdb/` | Doppler credentials | Read-only |
| `/scripts/` | Backup script execution | Read-only |

### Backup Files

#### File Specifications

| File | Schedule | Retention | Size (Typical) |
|------|----------|-----------|----------------|
| `nightly_backup.surql.gz` | Daily 2:00 AM | 24 hours (overwrite) | 1-10 MB |
| `weekly_backup.surql.gz` | Sunday 3:00 AM | 7 days (overwrite) | 1-10 MB |

#### File Format

- **Format**: Gzip-compressed SurrealQL export
- **Encoding**: UTF-8
- **Compression**: gzip level 6
- **Validation**: Pre-compression integrity check

### Environment Variables

#### Required Configuration

```bash
# Health monitoring port
SURREALDB_BACKUP_HEALTH_PORT=8081

# Backup storage location
SURREALDB_BACKUP_PATH=/volume1/docker/backups/surrealdb

# Resource constraints
SURREALDB_BACKUP_MEMORY_LIMIT=256M

# User permissions
PUID=1000
PGID=1000

# Timezone
TZ=UTC
```

#### Internal Environment

```bash
# SurrealDB connection
SURREALDB_ENDPOINT=http://core-surrealdb:8000

# Health server port (internal)
HEALTH_CHECK_PORT=8080
```

### Keyvault Structure

#### Required Secrets

| Secret | Purpose | Example |
|--------|---------|---------|
| `/keyvault/surrealdb/username` | SurrealDB root username | `root` |
| `/keyvault/surrealdb/password` | SurrealDB root password | `secure_password` |
| `/keyvault/surrealdb/namespace` | Target namespace | `core` |
| `/keyvault/surrealdb/database` | Target database | `services` |

### API Endpoints

#### Health Check Endpoint

**URL**: `http://localhost:8081/health`

**Response Format**:

```json
{
  "status": "healthy|degraded|unhealthy",
  "last_backup": "2024-01-01T02:00:00Z",
  "backup_files": {
    "nightly": {
      "exists": true,
      "size": "2.1MB",
      "modified": "2024-01-01T02:00:00Z"
    },
    "weekly": {
      "exists": true,
      "size": "2.0MB",
      "modified": "2024-01-01T03:00:00Z"
    }
  }
}
```

**Status Codes**:

- `200 OK`: Service healthy, recent backup completed
- `503 Service Unavailable`: Service degraded or backup failures

### Command Reference

#### Backup Scripts

```bash
# Manual backup execution
/scripts/backup-nightly.sh    # Execute nightly backup
/scripts/backup-weekly.sh     # Execute weekly backup

# Restore operations
/scripts/restore-backup.sh nightly           # Interactive restore
/scripts/restore-backup.sh nightly --force   # Automated restore
/scripts/restore-backup.sh nightly --verify  # Integrity check only

# Health monitoring
/scripts/health-server.sh     # Start health HTTP server
```

#### Docker Operations

```bash
# Container management
docker exec core-surrealdb-backup [command]
docker logs core-surrealdb-backup
docker restart core-surrealdb-backup

# Log access
docker exec core-surrealdb-backup tail -f /logs/surrealdb-backup/backup.log
docker exec core-surrealdb-backup cat /logs/surrealdb-backup/health.log
```

---

## Troubleshooting

### Common Issues

#### Backup Service Won't Start

**Symptoms**: Container exits immediately or fails to start

**Diagnosis**:

```bash
# Check container logs
docker logs core-surrealdb-backup

# Verify dependencies
docker-compose ps doppler-core surrealdb

# Check volume permissions
ls -la /volume1/docker/backups/surrealdb/
```

**Solutions**:

1. Ensure Doppler and SurrealDB services are running
2. Verify backup directory exists and has correct permissions
3. Check environment variable configuration in `.env`

#### Backup Fails with Authentication Error

**Symptoms**: Backup logs show authentication failures

**Diagnosis**:

```bash
# Check keyvault contents
docker exec core-surrealdb-backup ls -la /keyvault/surrealdb/

# Test SurrealDB connectivity
docker exec core-surrealdb-backup curl -f http://core-surrealdb:8000/health

# Review authentication in logs
docker exec core-surrealdb-backup grep -i auth /logs/surrealdb-backup/backup.log
```

**Solutions**:

1. Verify Doppler keyvault is populated with correct credentials
2. Confirm SurrealDB service is accessible on internal network
3. Check SurrealDB credentials are valid

#### Health Check Returns 503

**Symptoms**: Health endpoint returns service unavailable

**Diagnosis**:

```bash
# Check health server process
docker exec core-surrealdb-backup ps aux | grep health-server

# Test internal endpoint
docker exec core-surrealdb-backup curl -f http://localhost:8080/health

# Review health logs
docker exec core-surrealdb-backup cat /logs/surrealdb-backup/health.log
```

**Solutions**:

1. Restart backup service to reinitialize health server
2. Check if recent backup completed successfully
3. Verify cron daemon is running

#### Backup Files Not Created

**Symptoms**: Backup directory remains empty after scheduled runs

**Diagnosis**:

```bash
# Check cron execution
docker exec core-surrealdb-backup ps aux | grep cron

# Review cron logs
docker exec core-surrealdb-backup tail -f /logs/surrealdb-backup/cron.log

# Test manual backup
docker exec core-surrealdb-backup /scripts/backup-nightly.sh
```

**Solutions**:

1. Verify cron daemon is running inside container
2. Check volume mount permissions (PUID=1000)
3. Ensure SurrealDB connectivity and authentication

#### High Memory Usage

**Symptoms**: Container approaches memory limit or gets killed

**Diagnosis**:

```bash
# Monitor resource usage
docker stats core-surrealdb-backup

# Check memory limit configuration
docker inspect core-surrealdb-backup | grep -i memory
```

**Solutions**:

1. Increase `SURREALDB_BACKUP_MEMORY_LIMIT` in environment configuration
2. Monitor backup file sizes for growth trends
3. Consider adjusting backup frequency if database is very large

### Log Analysis

#### Structured Log Format

Backup logs use JSON format for integration with monitoring systems:

```json
{
  "timestamp": "2024-01-01T02:00:00Z",
  "level": "INFO",
  "operation": "backup_nightly",
  "status": "success",
  "file_size": "2.1MB",
  "duration": "15.2s",
  "validation": "passed"
}
```

#### Log Levels

- **INFO**: Normal operations and successful completions
- **WARN**: Non-critical issues that don't prevent operation
- **ERROR**: Failures that prevent backup completion
- **DEBUG**: Detailed operation information (when enabled)

#### Common Log Patterns

**Successful Backup**:

```json
{"level":"INFO","operation":"backup_start","timestamp":"2024-01-01T02:00:00Z"}
{"level":"INFO","operation":"validation_pass","timestamp":"2024-01-01T02:00:15Z"}
{"level":"INFO","operation":"backup_complete","file_size":"2.1MB","timestamp":"2024-01-01T02:00:30Z"}
```

**Authentication Failure**:

```json
{"level":"ERROR","operation":"auth_failed","error":"invalid credentials","timestamp":"2024-01-01T02:00:05Z"}
```

**Connectivity Issue**:

```json
{"level":"ERROR","operation":"connection_failed","endpoint":"http://core-surrealdb:8000","timestamp":"2024-01-01T02:00:05Z"}
```

---

## Maintenance

### Regular Tasks

#### Weekly Monitoring

```bash
# Check backup file sizes and timestamps
ls -lh /volume1/docker/backups/surrealdb/

# Review backup logs for errors
docker exec core-surrealdb-backup grep -i error /logs/surrealdb-backup/backup.log

# Verify health endpoint responsiveness
curl -w "Response time: %{time_total}s\n" http://localhost:8081/health
```

#### Monthly Testing

```bash
# Test restore procedures (verify only)
docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --verify
docker exec core-surrealdb-backup /scripts/restore-backup.sh weekly --verify

# Check container resource usage
docker stats --no-stream core-surrealdb-backup

# Review log file sizes
du -sh /volume1/docker/logs/surrealdb-backup/*
```

#### Quarterly Maintenance

```bash
# Update SurrealDB CLI (if newer version available)
# Check current version
docker exec core-surrealdb-backup surreal version

# Backup integrity verification with sample restore to test database
# This requires coordination with SurrealDB administrators

# Review and clean old log files if necessary
find /volume1/docker/logs/surrealdb-backup/ -name "*.log" -mtime +90 -delete
```

### Performance Monitoring

#### Backup Duration Tracking

Monitor backup completion times to identify performance degradation:

```bash
# Extract duration from recent backup logs
docker exec core-surrealdb-backup grep -o '"duration":"[^"]*"' /logs/surrealdb-backup/backup.log | tail -10
```

#### Disk Space Management

```bash
# Check available space in backup directory
df -h /volume1/docker/backups/surrealdb/

# Monitor backup file size trends
stat -c "%Y %s %n" /volume1/docker/backups/surrealdb/*.gz | sort -n
```

#### Health Endpoint Monitoring

```bash
# Set up monitoring script (example)
#!/bin/bash
while true; do
    if ! curl -f http://localhost:8081/health >/dev/null 2>&1; then
        echo "$(date): Backup service health check failed" >> /var/log/backup-monitor.log
    fi
    sleep 300  # Check every 5 minutes
done
```

### Update Procedures

#### SurrealDB CLI Updates

When updating the SurrealDB CLI version:

1. **Test in development environment first**
2. **Verify backup/restore compatibility**
3. **Update Dockerfile with new version**
4. **Rebuild and redeploy container**

#### Container Updates

```bash
# Pull latest base images
docker-compose pull

# Rebuild backup container
docker-compose build surrealdb-backup

# Rolling update (ensure no backup in progress)
docker-compose up -d surrealdb-backup
```

---

## Security Considerations

### Access Control

- **Container Security**: Runs as non-root user (PUID=1000)
- **Network Isolation**: Internal network only, no external access required
- **Credential Management**: All authentication via Doppler keyvault
- **File Permissions**: Backup files owned by specified PUID/PGID

### Data Protection

- **Encryption at Rest**: Backup files stored on host filesystem (inherit host encryption)
- **Secure Transport**: Internal network communication only
- **Credential Rotation**: Support for Doppler secret rotation
- **Audit Trail**: Structured logging for all operations

### Compliance Notes

- **Data Retention**: 2-file rolling strategy limits data retention automatically
- **Access Logging**: All backup operations logged with timestamps
- **Recovery Testing**: Verification procedures support compliance requirements

---

## Related Documentation

- [SurrealDB Backup Deployment Guide](SURREALDB_BACKUP_DEPLOYMENT.md)
- [Backup Implementation Details](infra/docker/apps/syno-core/scripts/backup/README.md)
- [Docker Compose Configuration](infra/docker/apps/syno-core/docker-compose.yml)
- [Container Specification](infra/docker/modules/components/surrealdb-backup/Dockerfile)

---

**Last Updated**: 2024
**Version**: 1.0
**Target Audience**: System administrators, DevOps engineers, developers
**Compatibility**: SurrealDB 1.0+, Docker 20.10+, Synology DSM 7.2+
