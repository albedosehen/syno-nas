# Unified Core Services for Synology NAS

A comprehensive unified Docker composition for Synology DSM 7.2+ that integrates **Portainer** (container management), **SurrealDB** (multi-model database), and **Doppler** (secrets management) into a cohesive core infrastructure stack.

## 🚀 Overview

This unified core stack provides the foundation services for your Synology NAS Docker environment:

- **🐳 Portainer CE LTS**: Web-based Docker container management interface
- **🗄️ SurrealDB**: Modern multi-model database with real-time capabilities  
- **🔐 Doppler**: Enterprise-grade secrets management and configuration
- **🔒 Security**: Network isolation, encrypted secrets, local-only access
- **📊 Monitoring**: Health checks, resource limits, comprehensive logging

### Key Features

✅ **Unified Management**: All core services in one composition  
✅ **Security First**: Doppler secrets integration, no hardcoded credentials  
✅ **Synology Optimized**: Proper PUID/PGID, volume paths, and permissions  
✅ **Production Ready**: Health checks, resource limits, restart policies  
✅ **Network Isolated**: Dedicated bridge network for service communication  
✅ **Scalable Design**: Foundation for additional service stacks  

## 📋 Prerequisites

### System Requirements

- **Synology NAS**: DS1520+ or compatible model
- **DSM Version**: 7.2 or later
- **Docker**: 20.10+ (available via Package Center)
- **Memory**: Minimum 2GB available RAM
- **Storage**: 1GB free space for containers and data

### Required Setup

1. **Docker Package**: Install from DSM Package Center
2. **SSH Access**: Enable SSH service in DSM Control Panel
3. **File Permissions**: Ensure Docker user has proper access rights
4. **Doppler Account**: Create account at [doppler.com](https://doppler.com)

## 🛠️ Installation

### Quick Start with Automated Deployment

For the fastest setup experience, use our automated deployment scripts:

```bash
# Connect to your Synology NAS
ssh admin@your-nas-ip

# Navigate to project directory
cd /volume1/docker/syno-nas/docker/compositions/core

# Make deployment script executable
chmod +x deploy.sh

# Run automated deployment
./deploy.sh
```

**Windows PowerShell Alternative:**

```powershell
# Navigate to project directory
cd C:\path\to\syno-nas\docker\compositions\core

# Run PowerShell deployment script
.\deploy.ps1
```

### Manual Installation (Detailed)

#### Step 1: Prepare Directory Structure

```bash
# Connect to your Synology NAS
ssh admin@your-nas-ip

# Create core services directory
sudo mkdir -p /volume1/docker/core/{portainer,surrealdb,doppler}/{data,config}
sudo mkdir -p /volume1/docker/backups/core

# Set proper permissions
sudo chown -R 1000:1000 /volume1/docker/core
sudo chmod -R 755 /volume1/docker/core
sudo chown -R 1000:1000 /volume1/docker/backups/core
sudo chmod -R 755 /volume1/docker/backups/core
```

#### Step 2: Clone and Configure

```bash
# Navigate to project directory
cd /volume1/docker/syno-nas/docker/compositions/core

# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

#### Step 3: Configure Doppler Integration

**Quick Setup**: See [`DOPPLER_SETUP.md`](./DOPPLER_SETUP.md) for comprehensive configuration guide.

1. **Create Doppler Project**:

   ```bash
   # Login to Doppler CLI (optional for setup verification)
   doppler login
   
   # Create project and config
   doppler projects create core-services
   doppler configs create dev --project core-services
   ```

2. **Generate Service Token**:
   - Visit [Doppler Dashboard](https://dashboard.doppler.com)
   - Navigate to: Project → Config → Access → Service Tokens
   - Create token with read access
   - Copy token to `.env` file

3. **Add Initial Secrets**:

   ```bash
   # Set database credentials in Doppler
   doppler secrets set SURREALDB_USER=admin --project core-services --config dev
   doppler secrets set SURREALDB_PASS=your_secure_password --project core-services --config dev
   ```

#### Step 4: Configure Environment Variables

Edit the `.env` file with your specific values:

```env
# System Configuration
PUID=1000                    # Your user ID: id username
PGID=1000                    # Your group ID: id username
TZ=America/New_York          # Your timezone

# Doppler Configuration
DOPPLER_TOKEN=dp.pt.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
DOPPLER_PROJECT=core-services
DOPPLER_CONFIG=dev

# Port Configuration (ensure no conflicts)
PORTAINER_PORT=9000          # Portainer web UI
PORTAINER_EDGE_PORT=8000     # Portainer Edge Agent
SURREALDB_PORT=8001          # SurrealDB API/UI (avoid conflict with Portainer)

# Storage Paths (absolute paths recommended)
PORTAINER_DATA_PATH=/volume1/docker/core/portainer/data
SURREALDB_DATA_PATH=/volume1/docker/core/surrealdb/data
SURREALDB_CONFIG_PATH=/volume1/docker/core/surrealdb/config
```

#### Step 5: Deploy Core Services

**Automated Deployment:**

```bash
# Use deployment script (recommended)
./deploy.sh

# Or manual deployment
docker-compose up -d

# Verify deployment
./status.sh
```

## 🤖 Deployment Automation

The unified core stack includes comprehensive automation scripts for easy management:

### Available Scripts

| Script | Purpose | Platform |
|--------|---------|----------|
| [`deploy.sh`](./deploy.sh) | Automated deployment and setup | Linux/Synology |
| [`deploy.ps1`](./deploy.ps1) | Automated deployment for Windows | PowerShell |
| [`stop.sh`](./stop.sh) | Graceful service shutdown | Linux/Synology |
| [`backup.sh`](./backup.sh) | Automated data backup | Linux/Synology |
| [`logs.sh`](./logs.sh) | Centralized log viewing | Linux/Synology |
| [`status.sh`](./status.sh) | Health and status monitoring | Linux/Synology |
| [`update.sh`](./update.sh) | Service update automation | Linux/Synology |

### Usage Examples

```bash
# Deploy services with automatic prerequisite checking
./deploy.sh

# Check system status and health
./status.sh

# View logs for all services
./logs.sh

# View logs for specific service
./logs.sh portainer

# Create backup of all data
./backup.sh

# Update all services to latest versions
./update.sh

# Gracefully stop all services
./stop.sh
```

### Script Features

✅ **Error Handling**: Comprehensive error checking and recovery
✅ **Prerequisites**: Automatic validation of system requirements
✅ **Help Documentation**: Built-in usage information (`--help`)
✅ **Logging**: Detailed operation logs with timestamps
✅ **Rollback**: Automatic rollback on deployment failures
✅ **Cross-Platform**: Linux/Synology and Windows PowerShell support

## 🌐 Access Services

After successful deployment, access your services:

### Portainer

- **URL**: `http://your-nas-ip:9000`
- **Initial Setup**: Create admin account on first visit
- **Features**: Container management, image registry, network configuration

### SurrealDB

- **API Endpoint**: `http://your-nas-ip:8001`
- **WebSocket**: `ws://your-nas-ip:8001/rpc`
- **Authentication**: Uses Doppler-managed credentials
- **Features**: Multi-model queries, real-time subscriptions, ACID transactions

### Doppler (Internal Service)

- **Purpose**: Secrets injection for other services
- **Access**: No direct UI access (security by design)
- **Management**: Via Doppler Dashboard or CLI

## 🔧 Configuration Management

### Environment Variables

The unified stack supports extensive configuration through environment variables:

```env
# Resource Limits
PORTAINER_MEMORY_LIMIT=512M
SURREALDB_MEMORY_LIMIT=1G

# Network Configuration
CORE_NETWORK_SUBNET=172.20.0.0/16
LOCAL_NETWORK_ONLY=true

# Security Settings
ENABLE_SECURITY_HEADERS=true
ENABLE_RATE_LIMITING=true

# Backup Configuration
BACKUP_PATH=/volume1/docker/backups/core
BACKUP_RETENTION_DAYS=30
```

### Secrets Management with Doppler

All sensitive configuration is managed through Doppler:

```bash
# View current secrets
doppler secrets --project core-services --config dev

# Update database password
doppler secrets set SURREALDB_PASS=new_secure_password

# Restart services to apply changes
docker-compose restart surrealdb
```

### Service Dependencies

The composition ensures proper startup order:

1. **Doppler** starts first (secrets provider)
2. **SurrealDB** starts after Doppler is healthy
3. **Portainer** starts after Doppler is healthy

## 🔒 Security Features

### Network Isolation

- Dedicated `core-network` bridge network
- Internal service communication only
- No external network access by default

### Secrets Management

- No hardcoded credentials in compose files
- Doppler integration for encrypted secret storage
- Environment-based secret injection

### Access Control

- Local network access only by default
- Proper PUID/PGID for file permissions
- Read-only Docker socket access for Portainer

### Container Security

- Non-root user execution where possible
- Resource limits to prevent resource exhaustion
- Health checks for service monitoring

## 📊 Monitoring and Maintenance

### Health Monitoring

```bash
# Check service status
docker-compose ps

# View service health
docker-compose exec portainer wget -qO- http://localhost:9000/
docker-compose exec surrealdb curl -f http://localhost:8000/health
docker-compose exec doppler doppler --version

# Monitor resource usage
docker stats core-portainer core-surrealdb core-doppler
```

### Log Management

```bash
# View all service logs
docker-compose logs

# Follow specific service logs
docker-compose logs -f portainer
docker-compose logs -f surrealdb
docker-compose logs -f doppler

# Export logs for analysis
docker-compose logs --since=24h > core-services-logs.txt
```

### Backup Procedures

```bash
# Create backup directory
mkdir -p /volume1/docker/backups/core/$(date +%Y%m%d)

# Backup Portainer data
tar -czf /volume1/docker/backups/core/$(date +%Y%m%d)/portainer-backup.tar.gz \
    -C /volume1/docker/core/portainer/data .

# Backup SurrealDB data
tar -czf /volume1/docker/backups/core/$(date +%Y%m%d)/surrealdb-backup.tar.gz \
    -C /volume1/docker/core/surrealdb/data .

# Backup configuration
cp .env /volume1/docker/backups/core/$(date +%Y%m%d)/env-backup
```

## 🚨 Troubleshooting

### Quick Diagnostics

Use the automated status checker for immediate diagnostics:

```bash
# Run comprehensive system check
./status.sh --verbose

# Check specific service health
./status.sh portainer
./status.sh surrealdb
./status.sh doppler
```

### Common Issues

#### 🔴 Services Won't Start

**Symptoms**: Containers exit immediately or fail to start

```bash
# Automated diagnosis
./status.sh --diagnose

# Manual checks
sudo systemctl status docker          # Check Docker daemon
ls -la /volume1/docker/core/          # Verify permissions
netstat -tulpn | grep -E ':(8000|8001|9000)'  # Check port conflicts

# Fix common issues
sudo chown -R 1000:1000 /volume1/docker/core  # Fix permissions
sudo systemctl restart docker                  # Restart Docker
```

**Synology-Specific Issues:**

```bash
# Check DSM Docker package status
sudo synoservice --status pkgctl-Docker

# Restart Docker service on DSM
sudo synoservice --restart pkgctl-Docker

# Check DSM firewall rules
sudo iptables -L | grep -E '(8000|8001|9000)'
```

#### 🔑 Doppler Authentication Fails

**Symptoms**: "Authentication failed" errors in logs

```bash
# Verify token format and validity
echo $DOPPLER_TOKEN | grep "^dp\.pt\."         # Check format
docker-compose exec doppler doppler me          # Test authentication
docker-compose exec doppler doppler configs --project core-services  # Verify access

# Debug token issues
export DOPPLER_TOKEN="your_token_here"
doppler me                                      # Test locally first

# Regenerate token if needed
# 1. Visit Doppler Dashboard
# 2. Navigate to Project → Config → Access → Service Tokens
# 3. Create new token with appropriate permissions
# 4. Update .env file with new token
```

#### 🗄️ Database Connection Issues

**Symptoms**: Connection timeouts, authentication errors

```bash
# Check SurrealDB container health
./status.sh surrealdb
docker-compose logs surrealdb

# Test database connectivity
curl -X POST http://your-nas-ip:8001/sql \
  -H "Content-Type: application/json" \
  -u "admin:your_password" \
  -d '{"sql": "INFO FOR KV;"}'

# Reset database if corrupted
./stop.sh
sudo rm -rf /volume1/docker/core/surrealdb/data/*
./deploy.sh
```

#### 🐳 Portainer Access Problems

**Symptoms**: Web UI not accessible, Docker socket errors

```bash
# Check container and socket access
docker-compose ps portainer
docker-compose exec portainer ls -la /var/run/docker.sock

# Reset Portainer admin password
./stop.sh
docker run --rm -v core_portainer_data:/data portainer/helper-reset-password
./deploy.sh

# Fix Docker socket permissions (Synology)
sudo chmod 666 /var/run/docker.sock
```

#### 🌐 Network Connectivity Issues

**Symptoms**: Services can't communicate, DNS resolution fails

```bash
# Check core network
docker network inspect core-network

# Test inter-service connectivity
docker-compose exec portainer ping core-surrealdb
docker-compose exec surrealdb ping core-doppler

# Recreate network if needed
./stop.sh
docker network rm core-network
./deploy.sh
```

### Performance Optimization

#### Resource Tuning

Monitor and adjust resource allocation:

```bash
# Monitor current usage
./status.sh --resources
docker stats core-portainer core-surrealdb core-doppler

# Adjust memory limits in .env based on your system
PORTAINER_MEMORY_LIMIT=256M          # Reduce for low-memory systems
SURREALDB_MEMORY_LIMIT=2G            # Increase for heavy database usage
DOPPLER_MEMORY_LIMIT=128M            # Usually sufficient

# Apply changes
docker-compose up -d
```

#### Storage Optimization

```bash
# Use SSD storage for better performance
SURREALDB_DATA_PATH=/volume1/ssd-cache/surrealdb/data
PORTAINER_DATA_PATH=/volume1/ssd-cache/portainer/data

# Regular maintenance
./backup.sh                          # Automated backup script
docker system prune -f               # Remove unused containers/images
docker volume prune -f               # Remove unused volumes

# Monitor disk usage
df -h /volume1/docker/core/
du -sh /volume1/docker/core/*/data
```

#### Network Performance

```bash
# Optimize network settings for Synology
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
sysctl -p

# Use host network for better performance (less secure - dev only)
# Modify docker-compose.yml:
# network_mode: host  # Only for development environments
```

### Synology DSM Specific Troubleshooting

#### DSM Integration Issues

```bash
# Check DSM Docker package version
synoservice --status pkgctl-Docker

# Verify shared folder permissions
sudo ls -la /volume1/docker/
sudo cat /etc/passwd | grep docker

# Fix DSM-specific permission issues
sudo usermod -a -G docker admin
sudo systemctl restart docker
```

#### Task Scheduler Integration

For automated maintenance on DSM:

```bash
# Add to DSM Task Scheduler (Control Panel → Task Scheduler)
# Daily backup task:
/volume1/docker/syno-nas/docker/compositions/core/backup.sh

# Weekly cleanup task:
docker system prune -f && docker volume prune -f

# Health check every 6 hours:
/volume1/docker/syno-nas/docker/compositions/core/status.sh --alert
```

#### SSL/TLS with DSM Reverse Proxy

Configure DSM reverse proxy for HTTPS access:

```text
1. Control Panel → Application Portal → Reverse Proxy
2. Create new rule:
   - Source: your-domain.com/portainer
   - Destination: localhost:9000
3. Enable HTTPS and certificates
4. Update firewall rules if needed
```

### Advanced Debugging

#### Enable Debug Mode

```bash
# Enable verbose logging
export LOG_LEVEL=DEBUG
export DEV_MODE=true

# Restart with debug settings
./stop.sh
./deploy.sh

# Monitor debug logs
./logs.sh --debug
```

#### Container Inspection

```bash
# Inspect container configurations
docker inspect core-portainer
docker inspect core-surrealdb
docker inspect core-doppler

# Check environment variables
docker-compose exec portainer printenv
docker-compose exec surrealdb printenv
docker-compose exec doppler printenv
```

#### Network Analysis

```bash
# Analyze network traffic
sudo tcpdump -i docker0 port 9000 or port 8001

# Check DNS resolution
docker-compose exec portainer nslookup core-surrealdb
docker-compose exec surrealdb nslookup core-doppler

# Inspect network routing
docker-compose exec portainer route -n
```

### Recovery Procedures

#### Complete System Recovery

```bash
# Stop all services
./stop.sh

# Backup current state
./backup.sh

# Remove all containers and networks
docker-compose down --volumes --remove-orphans
docker network rm core-network

# Restore from backup (if needed)
# tar -xzf /volume1/docker/backups/core/YYYYMMDD/portainer-backup.tar.gz -C /volume1/docker/core/portainer/data/
# tar -xzf /volume1/docker/backups/core/YYYYMMDD/surrealdb-backup.tar.gz -C /volume1/docker/core/surrealdb/data/

# Redeploy services
./deploy.sh
```

#### Emergency Access

```bash
# Access containers directly for emergency fixes
docker exec -it core-portainer /bin/sh
docker exec -it core-surrealdb /bin/bash
docker exec -it core-doppler /bin/bash

# Direct database access (bypass authentication)
docker exec -it core-surrealdb surreal sql --endpoint http://localhost:8000
```

## 🔄 Updates and Upgrades

### Updating Services

```bash
# Pull latest images
docker-compose pull

# Restart with new images
docker-compose up -d

# Verify updates
docker-compose ps
docker images | grep -E "(portainer|surrealdb|doppler)"
```

### Configuration Updates

```bash
# Update environment variables
nano .env

# Reload configuration
docker-compose up -d

# Verify changes
docker-compose config
```

## 🔗 Integration with Other Services

### Adding Media Services

```bash
# Create media stack that references core network
networks:
  default:
    external: true
    name: core-network
```

### Database Integration

```yaml
# Example service using SurrealDB
services:
  my-app:
    environment:
      - DATABASE_URL=http://core-surrealdb:8000
    networks:
      - core-network
```

### Secrets Integration

```yaml
# Example service using Doppler secrets
services:
  my-app:
    environment:
      - API_KEY=${API_KEY}  # Managed by Doppler
```

## 📚 Additional Resources

### Documentation

- [Portainer Documentation](https://docs.portainer.io/)
- [SurrealDB Documentation](https://surrealdb.com/docs)
- [Doppler Documentation](https://docs.doppler.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/)

### Community

- [Synology Community](https://community.synology.com/)
- [SurrealDB Discord](https://discord.gg/surrealdb)
- [Portainer Community](https://www.portainer.io/community)

---

**Project Status**: Production Ready  
**Version**: 1.0.0  
**Last Updated**: 2024  
**Compatibility**: Synology DSM 7.2+, Docker 20.10+

**License**: MIT License - Use, modify, and distribute according to your needs.
