# SurrealDB Rolling Backup Solution

## Overview

This directory contains the complete implementation of the SurrealDB rolling backup solution for syno-core infrastructure. The solution provides automated, validated, and compressed backups with a rolling 2-file strategy.

## Architecture

- **Rolling Strategy**: 2 backup files total (`nightly_backup.surql.gz`, `weekly_backup.surql.gz`)
- **Scheduling**: Container-based cron with staggered timing (2:00 AM daily, 3:00 AM Sunday)
- **Integration**: Doppler keyvault for secure authentication
- **Validation**: Export validation and gzip integrity checks
- **Monitoring**: Health check endpoint and structured JSON logging

## Files

### Core Scripts

- `backup-entrypoint.sh` - Container startup script
- `backup-utils.sh` - Shared utilities and functions
- `backup-nightly.sh` - Nightly backup execution
- `backup-weekly.sh` - Weekly backup execution
- `health-server.sh` - HTTP health check server
- `restore-backup.sh` - Manual restore utility

### Configuration

- `../../../modules/components/surrealdb-backup/Dockerfile` - Container image
- `../../../modules/components/surrealdb-backup/crontab` - Cron schedule
- `../docker-compose.yml` - Service definition (integrated)

## Usage

### Automatic Backups

Backups run automatically via cron schedule:

- **Nightly**: Every day at 2:00 AM (`0 2 * * *`)
- **Weekly**: Every Sunday at 3:00 AM (`0 3 * * 0`)

### Manual Restore

```bash
# Restore from nightly backup
docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly

# Restore from weekly backup with force flag
docker exec core-surrealdb-backup /scripts/restore-backup.sh weekly --force

# Verify backup integrity only
docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --verify
```

### Health Monitoring

```bash
# Check backup service health
curl http://localhost:8081/health

# View backup logs
docker logs core-surrealdb-backup
```

## File Locations

### Host Paths

- **Backups**: `/volume1/docker/backups/surrealdb/`
  - `nightly_backup.surql.gz`
  - `weekly_backup.surql.gz`
- **Logs**: `/volume1/docker/logs/surrealdb-backup/`
  - `backup.log` - Structured JSON logs
  - `health.log` - Health status
  - `cron.log` - Cron daemon logs

### Container Paths

- **Scripts**: `/scripts/` (mounted read-only)
- **Backups**: `/backups/` (read-write)
- **Keyvault**: `/keyvault/surrealdb/` (read-only)
- **Logs**: `/logs/surrealdb-backup/` (read-write)

## Authentication

Credentials are managed via Doppler keyvault:

- **Username**: `/keyvault/surrealdb/username`
- **Password**: `/keyvault/surrealdb/password`
- **Namespace**: `/keyvault/surrealdb/namespace`
- **Database**: `/keyvault/surrealdb/database`

## Environment Variables

Key configuration in `.env`:

```bash
SURREALDB_BACKUP_HEALTH_PORT=8081
SURREALDB_BACKUP_PATH=/volume1/docker/backups/surrealdb
SURREALDB_BACKUP_MEMORY_LIMIT=256M
```

## Troubleshooting

### Common Issues

1. **Backup fails with authentication error**
   - Check Doppler keyvault is populated
   - Verify SurrealDB credentials are correct

2. **Health check returns 503**
   - Check cron daemon is running
   - Verify recent backup completion
   - Review logs for errors

3. **Backup files not created**
   - Check volume permissions (PUID=1000)
   - Verify backup directory exists
   - Check SurrealDB connectivity

### Log Analysis

```bash
# View structured backup logs
docker exec core-surrealdb-backup tail -f /logs/surrealdb-backup/backup.log

# Check cron execution
docker exec core-surrealdb-backup tail -f /logs/surrealdb-backup/cron.log

# Verify health status
docker exec core-surrealdb-backup cat /logs/surrealdb-backup/health.log
```

## Recovery Procedures

### Emergency Restore

1. **Stop SurrealDB container**:

   ```bash
   docker stop core-surrealdb
   ```

2. **Choose backup file**:
   - Recent data: `nightly_backup.surql.gz`
   - Stable data: `weekly_backup.surql.gz`

3. **Clear existing database** (if corruption):

   ```bash
   rm -f /volume1/docker/core/surrealdb/data/database.db
   ```

4. **Start SurrealDB container**:

   ```bash
   docker start core-surrealdb
   ```

5. **Restore from backup**:

   ```bash
   docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --force
   ```

6. **Verify restoration**:

   ```bash
   docker exec core-surrealdb-backup /scripts/restore-backup.sh nightly --verify
   ```

## Security

- Non-root container execution (PUID=1000)
- Read-only keyvault access
- Network isolation within syno-core-network
- No external network access required
- Minimal exposed ports (health check only)

## Maintenance

- **Weekly**: Review backup logs and file sizes
- **Monthly**: Test restore procedures
- **Quarterly**: Verify backup integrity and update SurrealDB CLI if needed
