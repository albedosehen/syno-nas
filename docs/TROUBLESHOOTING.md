# Troubleshooting Guide - Synology NAS Docker Management

This comprehensive troubleshooting guide covers common issues you may encounter when running Docker containers on your Synology NAS, along with step-by-step solutions and diagnostic procedures.

## Table of Contents

- [General Troubleshooting](#general-troubleshooting)
- [Docker Service Issues](#docker-service-issues)
- [Container Problems](#container-problems)
- [Network Issues](#network-issues)
- [Storage and Permission Problems](#storage-and-permission-problems)
- [Performance Issues](#performance-issues)
- [Security-Related Problems](#security-related-problems)
- [Service-Specific Issues](#service-specific-issues)
- [Emergency Recovery](#emergency-recovery)

## General Troubleshooting

### Diagnostic Commands

#### Basic System Information

```bash
# Check DSM version
cat /etc/VERSION

# Check system resources
free -h
df -h
uptime

# Check Docker status
docker version
docker system info
```

#### Container Status Overview

```bash
# List all containers
docker ps -a

# Check Docker Compose services
docker-compose ps

# View system resource usage
docker stats --no-stream
```

### Log Collection

#### System Logs

```bash
# View system messages
dmesg | tail -20

# Check DSM logs
cat /var/log/messages | tail -50

# Docker daemon logs
journalctl -u docker -f
```

#### Container Logs

```bash
# View container logs
docker logs container-name

# Follow logs in real-time
docker logs -f container-name

# Get last 100 lines
docker logs --tail=100 container-name

# Docker Compose logs
docker-compose logs service-name
```

## Docker Service Issues

### Docker Daemon Not Running

#### Symptoms
- "Cannot connect to the Docker daemon" error
- Docker commands hang or timeout
- Container Manager shows Docker as stopped

#### Diagnosis

```bash
# Check Docker service status
sudo systemctl status docker

# Check if Docker socket exists
ls -la /var/run/docker.sock

# Check Docker daemon process
ps aux | grep dockerd
```

#### Solutions

```bash
# Start Docker service
sudo systemctl start docker

# Enable Docker to start on boot
sudo systemctl enable docker

# Restart Docker service
sudo systemctl restart docker

# If systemctl is not available on older DSM
sudo service docker start
```

### Docker Socket Permission Issues

#### Symptoms
- "Permission denied" when running Docker commands
- "Cannot connect to Docker daemon socket" error

#### Diagnosis

```bash
# Check socket permissions
ls -la /var/run/docker.sock

# Check user groups
groups $USER
id $USER
```

#### Solutions

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Apply group changes (logout/login required)
newgrp docker

# Alternative: Change socket permissions (temporary)
sudo chmod 666 /var/run/docker.sock
```

### Docker Storage Driver Issues

#### Symptoms
- Containers fail to start with storage errors
- "No space left on device" despite available space
- Container creation fails

#### Diagnosis

```bash
# Check Docker storage info
docker system df

# Check storage driver
docker info | grep "Storage Driver"

# Check available space
df -h /var/lib/docker
```

#### Solutions

```bash
# Clean up Docker resources
docker system prune -a

# Remove unused volumes
docker volume prune

# Remove unused networks
docker network prune

# If space issues persist, check Docker root directory
docker info | grep "Docker Root Dir"
```

## Container Problems

### Container Won't Start

#### Common Symptoms
- Container exits immediately after starting
- "Exited (1)" or other non-zero exit codes
- Container restarts continuously

#### Diagnosis Steps

```bash
# Check container status and exit code
docker ps -a

# View container logs
docker logs container-name

# Inspect container configuration
docker inspect container-name

# Check resource constraints
docker stats container-name
```

#### Common Solutions

##### Port Conflicts

```bash
# Check what's using the port
sudo netstat -tlnp | grep :PORT_NUMBER
sudo lsof -i :PORT_NUMBER

# Solution: Change port in docker-compose.yml or .env
PORTAINER_PORT=9001  # Instead of 9000
```

##### Volume Mount Issues

```bash
# Check if volume path exists
ls -la /path/to/volume

# Check permissions
ls -la /path/to/volume/..

# Fix permissions
sudo chown -R 1000:1000 /path/to/volume
sudo chmod -R 755 /path/to/volume
```

##### Memory/Resource Limits

```bash
# Check if container hit memory limit
docker inspect container-name | grep -A 10 "Memory"

# Increase memory limit in docker-compose.yml
deploy:
  resources:
    limits:
      memory: 1G  # Increase from 512M
```

### Container Performance Issues

#### Symptoms
- Slow response times
- High CPU or memory usage
- Container becomes unresponsive

#### Diagnosis

```bash
# Monitor real-time resource usage
docker stats

# Check container processes
docker exec container-name ps aux

# Check container resource limits
docker inspect container-name | grep -A 20 "Resources"
```

#### Solutions

```bash
# Increase resource limits
# In docker-compose.yml:
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '2.0'
    reservations:
      memory: 1G
      cpus: '1.0'

# Restart container with new limits
docker-compose up -d
```

## Network Issues

### Cannot Access Container Services

#### Symptoms
- Service not accessible via web browser
- Connection refused errors
- Timeouts when connecting

#### Diagnosis

```bash
# Check if container is running
docker ps | grep container-name

# Check port mappings
docker port container-name

# Test local connectivity
curl -I http://localhost:9000

# Check if port is listening
sudo netstat -tlnp | grep :9000
```

#### Solutions

##### Firewall Issues

```bash
# Check DSM firewall settings
# Control Panel → Security → Firewall

# Test connectivity from another machine
telnet nas-ip 9000

# Temporarily disable firewall for testing
# (Re-enable after testing!)
```

##### Network Configuration

```bash
# Check Docker networks
docker network ls

# Inspect network configuration
docker network inspect bridge

# Recreate network if needed
docker-compose down
docker network prune
docker-compose up -d
```

##### Port Binding Issues

```yaml
# Ensure correct port binding in docker-compose.yml
ports:
  - "9000:9000"  # host:container
  # NOT: "9000"  # This only exposes internally
```

### DNS Resolution Problems

#### Symptoms
- Containers can't resolve external hostnames
- Inter-container communication fails
- Service discovery not working

#### Diagnosis

```bash
# Test DNS resolution inside container
docker exec container-name nslookup google.com

# Check container DNS settings
docker exec container-name cat /etc/resolv.conf

# Check Docker daemon DNS settings
docker info | grep -A 5 "DNS"
```

#### Solutions

```bash
# Set custom DNS in docker-compose.yml
services:
  portainer:
    dns:
      - 8.8.8.8
      - 8.8.4.4

# Or use Synology NAS IP as DNS
dns:
  - 192.168.1.1  # Your router/NAS IP
```

## Storage and Permission Problems

### Permission Denied Errors

#### Symptoms
- "Permission denied" when accessing files
- Container can't write to mounted volumes
- Configuration files can't be read

#### Diagnosis

```bash
# Check file/directory ownership
ls -la /volume1/docker/service-name/

# Check current user ID inside container
docker exec container-name id

# Check PUID/PGID settings
docker exec container-name env | grep -E "(PUID|PGID)"
```

#### Solutions

```bash
# Fix ownership (replace with your PUID:PGID)
sudo chown -R 1000:1000 /volume1/docker/service-name/data

# Fix permissions
sudo chmod -R 755 /volume1/docker/service-name/data

# For sensitive files
sudo chmod 600 /volume1/docker/service-name/.env

# Verify PUID/PGID in .env file
echo "PUID=$(id -u)" >> .env
echo "PGID=$(id -g)" >> .env
```

### Storage Space Issues

#### Symptoms
- "No space left on device" errors
- Container creation fails
- Cannot write to volumes

#### Diagnosis

```bash
# Check overall disk space
df -h

# Check Docker space usage
docker system df

# Check specific volume usage
du -sh /volume1/docker/

# Check inode usage
df -i
```

#### Solutions

```bash
# Clean up Docker resources
docker system prune -a

# Remove unused volumes
docker volume prune

# Clean up old container logs
truncate -s 0 /var/lib/docker/containers/*/*-json.log

# Configure log rotation in docker-compose.yml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### Volume Mount Issues

#### Symptoms
- Volumes not appearing in container
- Data not persisting between container restarts
- Mount point is empty

#### Diagnosis

```bash
# Check volume mounts
docker inspect container-name | grep -A 10 "Mounts"

# Verify host path exists
ls -la /volume1/docker/service-name/data

# Check volume configuration
docker volume inspect volume-name
```

#### Solutions

```bash
# Ensure host directory exists
mkdir -p /volume1/docker/service-name/data

# Use absolute paths in docker-compose.yml
volumes:
  - /volume1/docker/service-name/data:/app/data
  # NOT: ./data:/app/data (relative paths can be problematic)

# Check volume syntax
volumes:
  - source:/destination:options
  # Example: /host/path:/container/path:rw
```

## Performance Issues

### High CPU Usage

#### Symptoms
- System becomes slow or unresponsive
- High load averages
- Containers using excessive CPU

#### Diagnosis

```bash
# Monitor CPU usage
top
htop
docker stats

# Check container resource limits
docker inspect container-name | grep -A 10 "CpuShares"

# Identify CPU-intensive processes
docker exec container-name top
```

#### Solutions

```bash
# Set CPU limits in docker-compose.yml
deploy:
  resources:
    limits:
      cpus: '1.0'  # Limit to 1 CPU core
    reservations:
      cpus: '0.5'

# Use CPU shares for relative priority
cpu_shares: 512  # Default is 1024
```

### Memory Issues

#### Symptoms
- Out of memory errors
- Container killed by OOM killer
- System swapping heavily

#### Diagnosis

```bash
# Check memory usage
free -h
docker stats

# Check for OOM kills in logs
dmesg | grep -i "killed process"
docker logs container-name | grep -i "out of memory"

# Check swap usage
swapon -s
```

#### Solutions

```bash
# Increase memory limits
deploy:
  resources:
    limits:
      memory: 2G
    reservations:
      memory: 1G

# Monitor memory usage over time
docker stats --no-stream > memory-usage.log

# Add swap if necessary (be cautious on SSDs)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### I/O Performance Issues

#### Symptoms
- Slow file operations
- High I/O wait times
- Database performance issues

#### Diagnosis

```bash
# Monitor I/O usage
iostat -x 1

# Check disk usage per container
docker exec container-name df -h

# Monitor I/O in containers
docker exec container-name iotop
```

#### Solutions

```bash
# Use bind mounts instead of volumes for better performance
volumes:
  - /volume1/docker/app/data:/app/data
  # Instead of named volumes for performance-critical apps

# Optimize database containers
volumes:
  - /volume1/docker/db/data:/var/lib/mysql
tmpfs:
  - /var/lib/mysql/tmp  # Use tmpfs for temporary files
```

## Security-Related Problems

### SSL/TLS Certificate Issues

#### Symptoms
- HTTPS connection errors
- Certificate warnings in browser
- SSL handshake failures

#### Diagnosis

```bash
# Check certificate validity
openssl x509 -in certificate.crt -text -noout

# Test SSL connection
openssl s_client -connect nas-ip:443

# Check certificate in container
docker exec container-name ls -la /certs/
```

#### Solutions

```bash
# Generate self-signed certificate
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# Use Let's Encrypt for valid certificates
# Configure reverse proxy with automatic SSL

# Ensure proper certificate permissions
chmod 644 certificate.crt
chmod 600 private.key
chown root:docker certificate.crt private.key
```

### Authentication Issues

#### Symptoms
- Cannot log into services
- Authentication failures
- Session timeouts

#### Diagnosis

```bash
# Check authentication logs
docker logs container-name | grep -i auth

# Verify user database
docker exec container-name cat /app/users.db

# Check authentication configuration
docker exec container-name cat /app/config/auth.conf
```

#### Solutions

```bash
# Reset admin password (Portainer example)
docker stop portainer
docker run --rm -v portainer_data:/data portainer/helper-reset-password

# Verify authentication settings in .env
AUTH_METHOD=local
SESSION_TIMEOUT=8h

# Check file permissions on auth files
chmod 600 /path/to/auth/files
```

## Service-Specific Issues

### Portainer Issues

#### Cannot Access Web Interface

```bash
# Check if Portainer is running
docker ps | grep portainer

# Check port binding
docker port portainer

# Test local access
curl -I http://localhost:9000

# Check firewall
sudo netstat -tlnp | grep :9000
```

#### Database Connection Errors

```bash
# Check data volume permissions
ls -la docker/compositions/management/portainer/data/

# Fix permissions
sudo chown -R 1000:1000 docker/compositions/management/portainer/data/

# Restart with clean data (WARNING: loses settings)
docker-compose down
sudo rm -rf data/
mkdir data
docker-compose up -d
```

### Media Server Issues

#### Transcoding Problems

```bash
# Check hardware acceleration support
lscpu | grep -E "(vmx|svm)"  # Intel VT-x or AMD-V
lspci | grep -i vga

# Enable hardware acceleration in docker-compose.yml
devices:
  - /dev/dri:/dev/dri  # Intel QuickSync
# or
  - /dev/nvidia0:/dev/nvidia0  # NVIDIA GPU
```

#### Library Scanning Issues

```bash
# Check volume mounts for media
docker exec media-server ls -la /media/

# Verify permissions
ls -la /volume1/media/

# Fix media permissions
sudo chown -R 1000:1000 /volume1/media/
sudo chmod -R 755 /volume1/media/
```

## Emergency Recovery

### Container Recovery Procedures

#### Complete Service Recovery

```bash
# Stop all services
docker-compose down

# Backup current state
tar -czf emergency-backup-$(date +%Y%m%d).tar.gz .

# Clean up corrupted containers
docker system prune -a

# Restore from backup
tar -xzf known-good-backup.tar.gz

# Restart services
docker-compose up -d
```

#### Data Recovery

```bash
# Mount data volumes for inspection
docker run -it --rm -v service_data:/data alpine /bin/sh

# Copy data out for recovery
docker cp container-name:/app/data ./recovered-data/

# Restore from backup
docker cp ./backup-data/. container-name:/app/data/
```

### System Recovery

#### Docker Daemon Recovery

```bash
# Stop Docker daemon
sudo systemctl stop docker

# Backup Docker data
sudo tar -czf docker-backup.tar.gz /var/lib/docker/

# Reset Docker (CAUTION: Removes all containers/images)
sudo rm -rf /var/lib/docker/
sudo systemctl start docker

# Restore containers from compose files
cd /volume1/docker/syno-nas/
find . -name "docker-compose.yml" -execdir docker-compose up -d \;
```

#### Full System Recovery

```bash
# 1. Stop all Docker services
docker stop $(docker ps -aq)

# 2. Backup configuration
tar -czf config-backup.tar.gz docker/compositions/

# 3. Clean Docker environment
docker system prune -a --volumes

# 4. Restore from project backup
tar -xzf project-backup.tar.gz

# 5. Redeploy services incrementally
cd docker/compositions/management/portainer/
docker-compose up -d

# Wait and verify each service before proceeding
```

## Diagnostic Scripts

### Automated Health Check

```bash
#!/bin/bash
# health-check.sh - Comprehensive system health check

echo "=== Docker Health Check ==="
echo "Date: $(date)"
echo

# Check Docker daemon
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker daemon not running"
    exit 1
else
    echo "✅ Docker daemon running"
fi

# Check container status
echo
echo "=== Container Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check resource usage
echo
echo "=== Resource Usage ==="
echo "Memory:"
free -h | grep Mem
echo "Disk:"
df -h | grep -E "(volume1|docker)"

# Check for errors in logs
echo
echo "=== Recent Errors ==="
docker ps -q | xargs -I {} docker logs --since 1h {} 2>&1 | grep -i error | tail -5

echo
echo "Health check completed"
```

### Log Analysis Script

```bash
#!/bin/bash
# analyze-logs.sh - Analyze container logs for issues

SERVICE_NAME="$1"
if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name>"
    exit 1
fi

echo "=== Log Analysis for $SERVICE_NAME ==="

# Get container logs
LOGS=$(docker-compose logs --tail=1000 "$SERVICE_NAME" 2>&1)

# Count error types
echo "Error Summary:"
echo "$LOGS" | grep -i error | wc -l | xargs echo "Total Errors:"
echo "$LOGS" | grep -i warning | wc -l | xargs echo "Total Warnings:"
echo "$LOGS" | grep -i fatal | wc -l | xargs echo "Total Fatal:"

# Show recent errors
echo
echo "Recent Errors:"
echo "$LOGS" | grep -i error | tail -10

# Check for common issues
echo
echo "Common Issues Found:"
echo "$LOGS" | grep -i "permission denied" && echo "- Permission issues detected"
echo "$LOGS" | grep -i "connection refused" && echo "- Connection issues detected"
echo "$LOGS" | grep -i "out of memory" && echo "- Memory issues detected"
echo "$LOGS" | grep -i "no space" && echo "- Disk space issues detected"
```

## Getting Help

### Information to Collect

When seeking help, collect this information:

```bash
# System information
cat /etc/VERSION > debug-info.txt
docker version >> debug-info.txt
docker system info >> debug-info.txt

# Container status
docker ps -a >> debug-info.txt
docker-compose ps >> debug-info.txt

# Resource usage
free -h >> debug-info.txt
df -h >> debug-info.txt

# Recent logs
docker-compose logs --tail=50 service-name >> debug-info.txt

# Configuration
cat .env >> debug-info.txt
cat docker-compose.yml >> debug-info.txt
```

### Support Resources

- **Project Documentation**: Check service-specific README files
- **Synology Community**: [community.synology.com](https://community.synology.com/)
- **Docker Documentation**: [docs.docker.com](https://docs.docker.com/)
- **Container-Specific Support**: Check official container documentation

### Emergency Contacts

- **System Administrator**: [Your contact info]
- **Backup Administrator**: [Backup contact]
- **Synology Support**: [Support case information]

---

**Troubleshooting Guide Version**: 1.0  
**Last Updated**: 2024  
**Compatibility**: Synology DSM 7.2+, Docker 20.10+

**Remember**: Always backup your data before attempting major troubleshooting steps, and test solutions in a non-production environment when possible.