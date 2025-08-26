# Docker Compositions

This directory contains Docker Compose service definitions organized by functional categories. Each service follows standardized patterns for configuration, deployment, and maintenance to ensure consistency across the entire infrastructure.

## Service Categories

### Management (`management/`)

Essential Docker management and monitoring tools:

- **[Portainer](management/portainer/)**: Web-based Docker container management interface
  - Complete container, image, and volume management
  - Network configuration and monitoring
  - Resource usage dashboards
  - User access control

*Planned additions*:

- Container monitoring solutions
- Log aggregation services
- Performance monitoring tools

### Media (`media/`)

Media server services and related management tools:

*Planned services*:

- **Plex Media Server**: Premium media streaming platform
- **Jellyfin**: Open-source media server alternative
- **Sonarr**: TV series management and automation
- **Radarr**: Movie management and automation
- **Lidarr**: Music management and automation
- **Prowlarr**: Indexer management for *arr services
- **Transmission/qBittorrent**: Download clients

### Productivity (`productivity/`)

Collaboration and productivity applications:

*Planned services*:

- **NextCloud**: Self-hosted cloud storage and collaboration
- **OnlyOffice**: Document collaboration suite
- **Bookstack**: Self-hosted documentation platform
- **Gitea**: Lightweight Git service
- **Kanboard**: Project management tool

### Networking (`networking/`)

Network infrastructure and security services:

*Planned services*:

- **WireGuard**: Modern VPN solution
- **Pi-hole**: Network-wide ad blocking
- **Nginx Proxy Manager**: Reverse proxy with SSL management
- **Traefik**: Modern reverse proxy and load balancer
- **Unbound**: Recursive DNS resolver

## Configuration Standards

### Environment Variables

All services use consistent environment variable patterns:

```env
# System Configuration (Required for all services)
PUID=1000                           # User ID for file permissions
PGID=1000                           # Group ID for file permissions
TZ=UTC                              # Timezone setting

# Network Configuration
[SERVICE_NAME]_PORT=9000            # Primary service port
[SERVICE_NAME]_ADDITIONAL_PORT=8000 # Additional ports if needed

# Storage Configuration
[SERVICE_NAME]_DATA_PATH=./data     # Data persistence location
[SERVICE_NAME]_CONFIG_PATH=./config # Configuration storage
BACKUP_PATH=/volume1/docker/backups/[service-name]

# Security Configuration
LOCAL_NETWORK_ONLY=true             # Restrict to local network access

# Resource Limits
[SERVICE_NAME]_MEMORY_LIMIT=512M    # Maximum memory usage
[SERVICE_NAME]_MEMORY_RESERVATION=256M # Guaranteed memory
```

### Security Defaults

All services are configured with security-first defaults:

- **Local Network Only**: Services accessible only from local network
- **Resource Limits**: Memory and CPU limits prevent resource exhaustion
- **Health Checks**: Automated health monitoring and restart policies
- **Proper Permissions**: Synology NAS-optimized user and group IDs
- **No External Access**: Management interfaces not exposed to internet

### Volume Management

Standardized volume configuration for Synology NAS:

```yaml
volumes:
  # Configuration persistence
  - ${SERVICE_CONFIG_PATH:-./config}:/app/config
  
  # Data persistence
  - ${SERVICE_DATA_PATH:-./data}:/app/data
  
  # Media access (for media services)
  - ${MEDIA_PATH:-/volume1/media}:/media:ro
  
  # Downloads access (for download managers)
  - ${DOWNLOADS_PATH:-/volume1/downloads}:/downloads
```

## Deployment Process

### Quick Deployment

```bash
# Navigate to service directory
cd [category]/[service-name]

# Configure environment
cp .env.example .env
nano .env  # Customize settings

# Deploy service
./deploy.sh
```

### Manual Deployment

```bash
# Configure environment
cp .env.example .env
# Edit .env with your specific settings

# Create data directories
mkdir -p data config

# Set proper permissions
chmod 755 data config
chown $(id -u):$(id -g) data config

# Deploy with Docker Compose
docker-compose up -d

# Verify deployment
docker-compose ps
```

## Service Management

### Starting Services

```bash
# Start specific service
cd [category]/[service-name]
docker-compose up -d

# Start all services in category
for dir in */; do
    cd "$dir" && docker-compose up -d && cd ..
done
```

### Stopping Services

```bash
# Stop specific service
cd [category]/[service-name]
docker-compose down

# Stop all services in category
for dir in */; do
    cd "$dir" && docker-compose down && cd ..
done
```

### Updating Services

```bash
# Update specific service
cd [category]/[service-name]
docker-compose pull && docker-compose up -d

# Update all services (planned automation)
find . -name "docker-compose.yml" -execdir docker-compose pull \; -execdir docker-compose up -d \;
```

## Backup and Maintenance

### Backup Procedures

Each service includes automated backup scripts:

```bash
# Backup specific service
cd [category]/[service-name]
./backup.sh

# Backup with service stop for consistency
./backup.sh --stop-service

# Backup with custom retention
./backup.sh --keep-days 30
```

### Maintenance Tasks

Regular maintenance procedures:

```bash
# Check service health
docker-compose ps

# View service logs
docker-compose logs -f [service-name]

# Check resource usage
docker stats

# Clean up unused resources
docker system prune -f
```

## Adding New Services

### Using the Service Template

1. **Choose Category**: Determine the appropriate functional category
2. **Create Directory**: Follow the standardized naming convention
3. **Use Template**: Copy from [`docs/SERVICE_TEMPLATE.md`](../../docs/SERVICE_TEMPLATE.md)
4. **Customize Configuration**: Adapt for specific service requirements
5. **Document Thoroughly**: Include comprehensive README.md
6. **Test Deployment**: Verify all deployment and backup procedures

### Service Requirements

New services must include:

- [ ] Complete README.md documentation
- [ ] Docker Compose configuration with Synology optimizations
- [ ] Environment template (.env.example) with documentation
- [ ] Automated deployment script (deploy.sh)
- [ ] Backup automation script (backup.sh)
- [ ] Health checks and resource limits
- [ ] Security configuration (local network only)
- [ ] Proper volume management

## Integration Patterns

### Inter-Service Communication

Services can communicate through Docker networks:

```yaml
# Example: Media server accessing download client
networks:
  media_network:
    external: true

services:
  media-server:
    networks:
      - media_network
```

### Shared Storage

Common storage patterns for related services:

```yaml
# Shared media library
volumes:
  - /volume1/media:/media:ro

# Shared download directory
volumes:
  - /volume1/downloads:/downloads
```

### Reverse Proxy Integration

Services can be configured for reverse proxy access:

```yaml
# Traefik labels for automatic service discovery
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.service.rule=Host(`service.local`)"
  - "traefik.http.services.service.loadbalancer.server.port=8080"
```

## Monitoring and Logging

### Health Monitoring

All services include health checks:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### Log Management

Centralized logging configuration:

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
    labels: "service,category"
```

## Troubleshooting

### Common Issues

1. **Port Conflicts**: Check port availability and update .env files
2. **Permission Problems**: Verify PUID/PGID settings and file ownership
3. **Resource Limits**: Monitor memory and CPU usage
4. **Network Issues**: Verify firewall settings and Docker networks

### Diagnostic Commands

```bash
# Check service status
docker-compose ps

# View service logs
docker-compose logs [service-name]

# Check resource usage
docker stats [container-name]

# Verify network connectivity
docker exec [container-name] ping [target-host]

# Check volume mounts
docker exec [container-name] ls -la /app/data
```

## Security Considerations

### Network Security

- **Firewall Configuration**: Services use non-standard ports when possible
- **Local Access Only**: Management interfaces restricted to local network
- **Network Isolation**: Services use dedicated Docker networks
- **SSL/TLS**: HTTPS encouraged for all web interfaces

### Data Protection

- **Regular Backups**: Automated backup procedures for all services
- **Encryption**: Sensitive data encryption at rest and in transit
- **Access Control**: Strong authentication and authorization
- **Audit Logging**: Comprehensive logging for security monitoring

### Container Security

- **Resource Limits**: Prevent resource exhaustion attacks
- **Non-Root Users**: Services run with unprivileged users when possible
- **Security Updates**: Regular container image updates
- **Minimal Attack Surface**: Only necessary ports and volumes exposed

## Future Enhancements

### Planned Features

- **Automated Updates**: Bulk update scripts for all services
- **Centralized Monitoring**: Integrated monitoring and alerting
- **Backup Orchestration**: Coordinated backup procedures
- **Configuration Management**: Centralized configuration templates
- **Service Discovery**: Automatic service registration and discovery

### Contributing

To contribute new services or improvements:

1. Follow the established patterns and templates
2. Include comprehensive documentation
3. Test thoroughly on Synology DSM 7.2+
4. Submit pull requests with detailed descriptions
5. Ensure security best practices are followed

---

**Compositions Version**: 1.0  
**Last Updated**: 2024  
**Service Count**: 1 (Portainer) + planned additions  
**Compatibility**: Synology DSM 7.2+, Docker 20.10+
