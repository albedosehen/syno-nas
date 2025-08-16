# Synology NAS Docker Management - Setup Guide

This comprehensive guide will walk you through setting up the Synology NAS Docker Management project from initial installation to running your first service.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Environment Configuration](#environment-configuration)
- [First Service Deployment](#first-service-deployment)
- [Security Configuration](#security-configuration)
- [Verification and Testing](#verification-and-testing)
- [Next Steps](#next-steps)

## Prerequisites

### Hardware Requirements

#### Minimum Requirements
- **RAM**: 2GB available (4GB recommended for multiple services)
- **Storage**: 10GB free space for project and basic services
- **CPU**: Any modern Synology NAS processor
- **Network**: Gigabit Ethernet recommended

#### Supported Models
- **Plus Series**: DS220+, DS420+, DS720+, DS920+, DS1520+, etc.
- **XS/XS+ Series**: DS1621xs+, DS1821+, DS2422+, etc.
- **Enterprise Series**: Most modern enterprise models
- **Value Series**: Some models (check Docker support)

### Software Requirements

#### Synology DSM
- **DSM Version**: 7.2 or later (required)
- **Container Manager**: Installed and enabled
- **SSH Service**: Enabled (recommended)
- **File Station**: Enabled for file management

#### User Permissions
- **Administrator Access**: Required for initial setup
- **Docker Permissions**: User must be in `docker` group
- **SSH Access**: For command-line management
- **Sudo Privileges**: For system-level operations

### Network Requirements

#### Firewall Configuration
- **Port 22**: SSH access (if using command line)
- **Port 9000**: Portainer web interface
- **Custom Ports**: As needed for additional services

#### Network Setup
- **Static IP**: Recommended for consistent access
- **DNS Configuration**: Proper DNS resolution
- **Local Network Access**: Most services configured for local-only access

## Initial Setup

### Step 1: Enable Required Services

1. **Access DSM Web Interface**:
   ```
   https://your-nas-ip:5001
   ```

2. **Install Container Manager**:
   - Open Package Center
   - Search for "Container Manager"
   - Install and start the package

3. **Enable SSH Service** (Recommended):
   - Control Panel → Terminal & SNMP
   - Enable SSH service
   - Set SSH port (default: 22)
   - Enable "Enable SSH service"

4. **Configure User Permissions**:
   - Control Panel → User & Group
   - Edit your user account
   - Add to "docker" group

### Step 2: Prepare Directory Structure

#### Option A: Command Line Setup (Recommended)

1. **Connect via SSH**:
   ```bash
   ssh admin@your-nas-ip
   ```

2. **Navigate to Docker directory**:
   ```bash
   # Standard Synology Docker location
   cd /volume1/docker
   
   # Create project directory
   mkdir -p syno-nas
   cd syno-nas
   ```

3. **Download/Clone Project**:
   ```bash
   # Option 1: Git clone (if git is available)
   git clone <repository-url> .
   
   # Option 2: Download and extract manually
   # (Upload via File Station and extract)
   ```

#### Option B: File Station Setup

1. **Open File Station** in DSM
2. **Navigate to** `/docker/` directory
3. **Create folder** named `syno-nas`
4. **Upload project files** to this directory
5. **Extract if using archive format**

### Step 3: Set Directory Permissions

```bash
# Make scripts executable
find . -name "*.sh" -type f -exec chmod +x {} \;

# Set proper ownership (replace 1000:1000 with your PUID:PGID)
sudo chown -R 1000:1000 .

# Set directory permissions
find . -type d -exec chmod 755 {} \;
find . -type f -exec chmod 644 {} \;
find . -name "*.sh" -exec chmod 755 {} \;
```

## Environment Configuration

### Step 1: Determine System Values

#### Find User and Group IDs

```bash
# Get current user ID and group ID
id

# Example output:
# uid=1000(admin) gid=1000(users) groups=1000(users),101(docker)
```

#### Determine Volume Paths

```bash
# List available volumes
ls -la /volume*

# Check Docker directory location
ls -la /volume1/docker
```

#### Set Timezone

```bash
# Check current timezone
cat /etc/TZ

# Common timezones:
# America/New_York
# Europe/London
# Asia/Tokyo
# UTC
```

### Step 2: Global Environment Setup

Create a global environment configuration:

```bash
# Create global config file
cat > .env.global << 'EOF'
# Global Configuration for Synology NAS Docker Management
# Copy values to individual service .env files

# System Configuration
PUID=1000
PGID=1000
TZ=UTC

# Synology Paths
SYNOLOGY_DOCKER_PATH=/volume1/docker
SYNOLOGY_DATA_PATH=/volume1/docker/data

# Network Configuration
LOCAL_NETWORK_ONLY=true

# Backup Configuration
BACKUP_PATH=/volume1/docker/backups
EOF
```

### Step 3: Firewall Configuration

#### Configure DSM Firewall

1. **Open Control Panel** → Security → Firewall
2. **Select your firewall profile** (or create one)
3. **Edit Rules**
4. **Add rules for required ports**:

   ```
   Port 9000: Portainer Web Interface
   Port 22: SSH (if enabled)
   Custom ports: As needed for services
   ```

5. **Apply firewall rules**

#### Test Network Access

```bash
# Test SSH connectivity
ssh admin@your-nas-ip

# Test port accessibility (from another machine)
telnet your-nas-ip 9000
```

## First Service Deployment

### Deploy Portainer (Recommended First Service)

Portainer provides a web interface for managing all Docker containers and is the recommended starting point.

#### Step 1: Navigate to Portainer Directory

```bash
cd /volume1/docker/syno-nas/docker/compositions/management/portainer
```

#### Step 2: Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

**Key configurations to update**:

```env
# Update with your values from previous steps
PUID=1000                           # Your user ID
PGID=1000                           # Your group ID
TZ=America/New_York                 # Your timezone
PORTAINER_PORT=9000                 # Web interface port
PORTAINER_DATA_PATH=./data          # Data storage location
SYNOLOGY_DOCKER_PATH=/volume1/docker # Docker volumes path
```

#### Step 3: Create Data Directory

```bash
# Create data directory
mkdir -p data

# Set proper permissions
sudo chown -R 1000:1000 data
chmod -R 755 data
```

#### Step 4: Deploy Portainer

```bash
# Deploy using Docker Compose
docker-compose up -d

# Verify deployment
docker-compose ps
```

#### Step 5: Verify Deployment

```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f portainer

# Check if service is responding
curl -I http://localhost:9000
```

## Security Configuration

### Container Security

#### Resource Limits

Ensure all services have proper resource limits:

```yaml
deploy:
  resources:
    limits:
      memory: 512M
    reservations:
      memory: 256M
```

#### Network Isolation

- Use custom networks for service isolation
- Restrict external access to management interfaces
- Implement proper firewall rules

### Data Security

#### Volume Permissions

```bash
# Set restrictive permissions for sensitive data
chmod 700 /path/to/sensitive/data
chown root:root /path/to/sensitive/data
```

#### Backup Security

```bash
# Create secure backup directory
mkdir -p /volume1/docker/backups
chmod 750 /volume1/docker/backups
chown admin:docker /volume1/docker/backups
```

### Access Control

#### Strong Authentication

- Use complex passwords (12+ characters)
- Enable two-factor authentication where available
- Regularly rotate credentials

#### User Separation

- Create separate users for different service categories
- Use least-privilege principle
- Monitor access logs regularly

## Verification and Testing

### Test Container Management

1. **Access Portainer Web Interface**:
   ```
   http://your-nas-ip:9000
   ```

2. **Complete Initial Setup**:
   - Create administrator account
   - Connect to local Docker environment
   - Verify environment status

3. **Test Basic Operations**:
   - View container list
   - Check system resources
   - Access container logs

### Verify System Health

```bash
# Check Docker service status
sudo systemctl status docker

# Verify container health
docker ps -a

# Check system resources
docker system df
free -h
df -h
```

### Test Network Connectivity

```bash
# Test local access
curl -I http://localhost:9000

# Test from another machine on network
curl -I http://your-nas-ip:9000

# Verify firewall is blocking external access (should fail)
# curl -I http://your-public-ip:9000
```

### Validate Security Settings

#### Check File Permissions

```bash
# Verify data directory permissions
ls -la docker/compositions/management/portainer/data

# Check configuration file permissions
ls -la docker/compositions/management/portainer/.env
```

#### Verify Network Security

```bash
# Check listening ports
sudo netstat -tlnp | grep :9000

# Verify firewall status
sudo iptables -L | grep 9000
```

## Next Steps

### Add Additional Services

1. **Browse Available Services**:
   ```bash
   ls docker/compositions/
   ```

2. **Choose Service Category** (media, productivity, networking)

3. **Follow Service-Specific Documentation**

4. **Deploy Using Established Patterns**

### Implement Monitoring

1. **Set Up Log Monitoring**:
   - Configure log rotation
   - Implement log aggregation
   - Set up alerting for errors

2. **Resource Monitoring**:
   - Monitor CPU and memory usage
   - Track disk space utilization
   - Set up performance alerts

### Backup Strategy

1. **Implement Regular Backups**:
   ```bash
   # Set up cron job for automated backups
   crontab -e
   
   # Add daily backup at 2 AM
   0 2 * * * /volume1/docker/syno-nas/docker/scripts/backup-all.sh
   ```

2. **Test Backup Restoration**:
   - Verify backup integrity
   - Practice restoration procedures
   - Document recovery processes

### Security Hardening

1. **Regular Updates**:
   - Update container images regularly
   - Apply DSM security updates
   - Monitor security advisories

2. **Access Auditing**:
   - Review access logs regularly
   - Monitor for suspicious activity
   - Implement intrusion detection

3. **Network Security**:
   - Consider VPN access for remote management
   - Implement network segmentation
   - Use SSL/TLS certificates

## Troubleshooting Common Setup Issues

### Docker Service Issues

```bash
# Restart Docker service
sudo systemctl restart docker

# Check Docker daemon logs
sudo journalctl -u docker -f

# Verify Docker socket permissions
ls -la /var/run/docker.sock
```

### Permission Problems

```bash
# Fix common permission issues
sudo chown -R $(id -u):$(id -g) .
sudo chmod -R 755 .
find . -name "*.sh" -exec chmod +x {} \;
```

### Network Connectivity Issues

```bash
# Check network configuration
ip addr show
ip route show

# Test DNS resolution
nslookup your-nas-ip
ping your-nas-ip

# Verify firewall rules
sudo iptables -L -n
```

### Storage Issues

```bash
# Check disk space
df -h

# Clean up Docker resources
docker system prune -a

# Check volume mounts
docker volume ls
docker volume inspect volume_name
```

## Support Resources

### Documentation

- [Main Project README](../README.md)
- [Security Best Practices](SECURITY.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Contributing Guidelines](../CONTRIBUTING.md)

### Community Resources

- [Synology Community](https://community.synology.com/)
- [Docker Documentation](https://docs.docker.com/)
- [Portainer Documentation](https://docs.portainer.io/)

### Emergency Recovery

In case of major issues:

1. **Stop all containers**: `docker stop $(docker ps -aq)`
2. **Backup current state**: `tar -czf emergency-backup.tar.gz .`
3. **Restore from known good backup**
4. **Restart services incrementally**
5. **Verify each service before proceeding**

---

**Setup Guide Version**: 1.0  
**Last Updated**: 2024  
**Compatibility**: Synology DSM 7.2+, Docker 20.10+