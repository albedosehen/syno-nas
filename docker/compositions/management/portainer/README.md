# Portainer for Synology NAS

A comprehensive Docker container management solution for Synology DSM 7.2, providing a web-based interface for managing Docker containers, images, networks, and volumes.

## Overview

Portainer Community Edition is a lightweight management UI that allows you to easily manage your Docker environments. This implementation is specifically optimized for Synology NAS systems running DSM 7.2, providing local network access only for enhanced security.

### Key Features

- **Web-based Docker Management**: Intuitive interface for container, image, and volume management
- **Local Network Security**: Configured for local network access only
- **Synology Optimized**: Proper volume mappings and permissions for DSM 7.2
- **Environment Variable Management**: Flexible configuration through `.env` files
- **Health Monitoring**: Built-in health checks and resource limits
- **Persistent Data**: Configuration and settings survive container restarts

## Prerequisites

### System Requirements

- **Synology NAS** with DSM 7.2 or later
- **Docker Package** installed and running (Container Manager in DSM 7.2)
- **SSH Access** to your Synology NAS (optional but recommended)
- **Minimum Resources**: 256MB RAM, 100MB storage

### Required Permissions

- SSH access with `sudo` privileges (for command-line setup)
- Docker permissions in DSM (for GUI setup)
- File Station access for configuration file management

## Installation

### Method 1: Command Line Installation (Recommended)

1. **Connect to your Synology NAS via SSH**:
   ```bash
   ssh admin@your-nas-ip
   ```

2. **Navigate to the project directory**:
   ```bash
   cd /volume1/docker/syno-nas/docker/compositions/management/portainer
   ```

3. **Configure environment variables**:
   ```bash
   # Copy the example environment file
   cp .env.example .env
   
   # Edit the configuration
   nano .env
   ```

4. **Set proper permissions** (if using custom data path):
   ```bash
   # Create data directory if it doesn't exist
   mkdir -p ./data
   
   # Set proper ownership (replace 1000:1000 with your PUID:PGID)
   sudo chown -R 1000:1000 ./data
   sudo chmod -R 755 ./data
   ```

5. **Deploy Portainer**:
   ```bash
   docker-compose up -d
   ```

### Method 2: Container Manager GUI Installation

1. **Open Container Manager** in DSM
2. **Navigate to Project** tab
3. **Create new project** named "portainer"
4. **Upload the docker-compose.yml** file
5. **Configure environment variables** in the GUI
6. **Start the project**

## Configuration

### Environment Variables (.env file)

Edit the `.env` file to customize your Portainer installation:

#### Essential Settings

```env
# User and Group IDs (check with 'id' command)
PUID=1000
PGID=1000

# Your timezone
TZ=America/New_York

# Web interface port
PORTAINER_PORT=9000

# Data storage path
PORTAINER_DATA_PATH=./data
```

#### Synology-Specific Settings

```env
# Docker volumes path (adjust based on your volume number)
SYNOLOGY_DOCKER_PATH=/volume1/docker

# For different volume numbers:
# SYNOLOGY_DOCKER_PATH=/volume2/docker
```

#### Security Configuration

```env
# Keep local access only for security
LOCAL_NETWORK_ONLY=true

# Resource limits
PORTAINER_MEMORY_LIMIT=512M
PORTAINER_MEMORY_RESERVATION=256M
```

### Advanced Configuration

#### Custom Data Directory

For production deployments, use absolute paths:

```env
PORTAINER_DATA_PATH=/volume1/docker/portainer/data
```

#### Multiple Volume Support

If you have multiple volumes, update the Docker volumes mapping:

```yaml
volumes:
  - /volume1/docker:/var/lib/docker/volumes:ro
  - /volume2/docker:/var/lib/docker/volumes2:ro
```

## First-Time Setup

### 1. Access Portainer Web Interface

After deployment, access Portainer at:
- **URL**: `http://your-nas-ip:9000`
- **Default Port**: 9000 (configurable via PORTAINER_PORT)

### 2. Initial Administrator Setup

1. **Create Admin User**:
   - Username: Choose your admin username
   - Password: Use a strong password (12+ characters)
   - Confirm password

2. **Environment Setup**:
   - Select "Docker (Local)" environment
   - Click "Connect"

### 3. Verify Environment

1. **Check Docker Connection**:
   - Navigate to "Environments" → "local"
   - Verify "Connected" status
   - Check system information

2. **Test Functionality**:
   - View existing containers
   - Check available images
   - Verify volume access

## Post-Deployment Configuration

### Security Hardening

1. **Disable User Registration**:
   - Settings → Authentication → Disable "Allow users to register"

2. **Set Session Timeout**:
   - Settings → Authentication → Set appropriate timeout (e.g., 8 hours)

3. **Enable Activity Logs**:
   - Settings → Feature → Enable "Show activity logs"

### User Management

1. **Create Additional Users** (if needed):
   - Users → Add user
   - Assign appropriate permissions

2. **Set Up Teams** (for multi-user environments):
   - Teams → Create team
   - Assign users and resources

### Backup Configuration

1. **Export Settings**:
   - Settings → Backup → Export configuration

2. **Schedule Regular Backups**:
   ```bash
   # Add to crontab for daily backups
   0 2 * * * /usr/bin/docker exec portainer tar -czf /data/backup-$(date +\%Y\%m\%d).tar.gz -C /data .
   ```

## Maintenance

### Regular Tasks

#### Health Checks

```bash
# Check container status
docker-compose ps

# View container logs
docker-compose logs portainer

# Check resource usage
docker stats portainer
```

#### Updates

```bash
# Pull latest image
docker-compose pull

# Recreate container with new image
docker-compose up -d

# Clean up old images
docker image prune
```

#### Backup Data

```bash
# Create backup directory
mkdir -p /volume1/docker/backups/portainer

# Backup Portainer data
tar -czf /volume1/docker/backups/portainer/portainer-backup-$(date +%Y%m%d).tar.gz -C ./data .
```

## Troubleshooting

### Common Issues

#### 1. Permission Denied Errors

**Symptoms**: Container fails to start, permission errors in logs

**Solution**:
```bash
# Check current ownership
ls -la ./data

# Fix ownership (replace with your PUID:PGID)
sudo chown -R 1000:1000 ./data
sudo chmod -R 755 ./data
```

#### 2. Port Already in Use

**Symptoms**: "Port already allocated" error

**Solution**:
```bash
# Check what's using the port
sudo netstat -tlnp | grep :9000

# Either stop the conflicting service or change PORTAINER_PORT in .env
```

#### 3. Cannot Connect to Docker Socket

**Symptoms**: "Cannot connect to Docker daemon" in Portainer

**Solution**:
```bash
# Check Docker socket permissions
ls -la /var/run/docker.sock

# Ensure Docker is running
sudo systemctl status docker

# Restart Portainer container
docker-compose restart portainer
```

#### 4. Web Interface Not Accessible

**Symptoms**: Cannot access http://nas-ip:9000

**Solution**:
```bash
# Check container is running
docker-compose ps

# Check firewall settings in DSM
# Control Panel → Security → Firewall → Edit Rules → Allow port 9000

# Check container logs
docker-compose logs portainer
```

### Logs and Debugging

#### View Portainer Logs

```bash
# Follow logs in real-time
docker-compose logs -f portainer

# View last 100 lines
docker-compose logs --tail=100 portainer

# Export logs to file
docker-compose logs portainer > portainer-logs.txt
```

#### Health Check Status

```bash
# Check health status
docker inspect portainer | grep -A 10 '"Health"'

# Manual health check
docker exec portainer wget --no-verbose --tries=1 --spider http://localhost:9000/
```

## Advanced Usage

### Integration with Other Services

#### Reverse Proxy Setup

If using a reverse proxy (like Nginx Proxy Manager):

1. **Update docker-compose.yml**:
   ```yaml
   labels:
     - "traefik.enable=true"  # Enable if using Traefik
     - "traefik.http.routers.portainer.rule=Host(`portainer.yourdomain.local`)"
   ```

2. **Configure proxy settings** in your reverse proxy

#### External Access (NOT RECOMMENDED)

For external access (use with caution):

1. **Update .env**:
   ```env
   LOCAL_NETWORK_ONLY=false
   ```

2. **Configure firewall** to allow external access
3. **Set up SSL** certificates for secure access

### Performance Optimization

#### Resource Monitoring

```bash
# Monitor container resources
docker stats portainer

# Check disk usage
du -sh ./data
```

#### Memory Optimization

For systems with limited RAM:

```env
PORTAINER_MEMORY_LIMIT=256M
PORTAINER_MEMORY_RESERVATION=128M
```

## Migration and Backup

### Full Backup Procedure

```bash
#!/bin/bash
# Complete Portainer backup script

BACKUP_DIR="/volume1/docker/backups/portainer"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="portainer_full_backup_${DATE}.tar.gz"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Stop Portainer (optional, for consistent backup)
docker-compose stop portainer

# Create backup
tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" \
    -C . \
    data \
    docker-compose.yml \
    .env

# Start Portainer
docker-compose start portainer

echo "Backup completed: ${BACKUP_DIR}/${BACKUP_FILE}"
```

### Restore Procedure

```bash
#!/bin/bash
# Restore Portainer from backup

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

# Stop Portainer
docker-compose down

# Backup current data (safety measure)
mv data data.backup.$(date +%Y%m%d_%H%M%S)

# Restore from backup
tar -xzf "$BACKUP_FILE"

# Start Portainer
docker-compose up -d

echo "Restore completed from: $BACKUP_FILE"
```

## Security Considerations

### Network Security

- **Local Network Only**: Default configuration restricts access to local network
- **No External Exposure**: Avoid exposing Portainer to the internet
- **Firewall Rules**: Configure DSM firewall to restrict access

### Data Security

- **Regular Backups**: Implement automated backup procedures
- **Access Control**: Use strong passwords and limit user access
- **Audit Logs**: Monitor activity logs for unauthorized access

### Container Security

- **Regular Updates**: Keep Portainer image updated
- **Resource Limits**: Prevent resource exhaustion attacks
- **Socket Access**: Monitor Docker socket access carefully

## Support

### Official Documentation

- [Portainer Documentation](https://docs.portainer.io/)
- [Synology Docker Guide](https://www.synology.com/en-us/dsm/packages/Docker)

### Community Resources

- [Portainer Community Forums](https://community.portainer.io/)
- [Synology Community](https://community.synology.com/)

### Project Issues

For issues specific to this Synology implementation, check:
- Configuration file syntax
- Environment variable values
- File permissions and ownership
- Docker service status

---

**Version**: 1.0  
**Last Updated**: 2024  
**Compatibility**: Synology DSM 7.2+, Portainer CE LTS