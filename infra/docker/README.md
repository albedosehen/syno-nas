# Docker Directory

This directory contains the complete Docker infrastructure for the Synology NAS Docker Management project, organized into logical subdirectories for easy management and scalability.

## Directory Structure

```plaintext
docker/
├── README.md                    # This file - Docker infrastructure overview
├── compositions/                # Service definitions organized by category
│   ├── management/             # Docker management tools (Portainer, monitoring)
│   ├── media/                  # Media servers and related services
│   ├── productivity/           # Productivity applications
│   └── networking/             # Network services (VPN, proxy, DNS)
├── dockerfiles/                # Custom Docker images and build contexts
├── scripts/                    # Utility scripts for Docker management
└── [Additional directories as needed]
```

## Service Organization

### Compositions Directory (`compositions/`)

Contains Docker Compose service definitions organized by functional categories:

- **Management**: Essential Docker management tools like Portainer for container management
- **Media**: Media servers (Plex, Jellyfin) and media management tools (*arr services)
- **Productivity**: Collaboration and productivity tools (NextCloud, office suites)
- **Networking**: Network infrastructure services (VPN, reverse proxy, DNS)

Each service follows a standardized structure for consistency and maintainability.

### Dockerfiles Directory (`dockerfiles/`)

Custom Docker images and build contexts for services that require specialized configurations or aren't available from official repositories.

### Scripts Directory (`scripts/`)

Automation and utility scripts for managing the Docker environment, including:

- Bulk operations across multiple services
- Maintenance and cleanup tasks
- Monitoring and health checks
- Backup automation

## Getting Started

### Quick Start

1. **Deploy Portainer** (recommended first step):

   ```bash
   cd compositions/management/portainer
   cp .env.example .env
   # Edit .env with your settings
   ./deploy.sh
   ```

2. **Access Portainer Web Interface**:

   ```plaintext
   http://your-nas-ip:9000
   ```

3. **Browse Available Services**:

   ```bash
   find compositions/ -name "docker-compose.yml" -printf "%h\n" | sort
   ```

### Service Management

Each service includes:

- **README.md**: Comprehensive documentation
- **docker-compose.yml**: Service definition
- **.env.example**: Configuration template
- **deploy.sh**: Automated deployment script
- **backup.sh**: Backup automation

## Standards and Conventions

### Environment Variables

All services use consistent environment variable naming:

- `PUID`/`PGID`: User and group IDs for file permissions
- `TZ`: Timezone configuration
- `[SERVICE]_PORT`: Service-specific port mappings
- `[SERVICE]_DATA_PATH`: Data persistence location
- `LOCAL_NETWORK_ONLY`: Security restriction flag

### Security Configuration

- **Local Network Only**: Services default to local network access
- **Resource Limits**: All services include memory and CPU limits
- **Health Checks**: Services include health monitoring
- **Proper Permissions**: Synology NAS-optimized file permissions

### Volume Management

- **Persistent Data**: Service data stored in dedicated directories
- **Configuration Persistence**: Settings survive container updates
- **Backup-Friendly**: Data organized for easy backup procedures
- **Synology Optimization**: Volume paths optimized for NAS storage

## Common Operations

### Deploying a New Service

```bash
# Navigate to service directory
cd compositions/[category]/[service-name]

# Configure environment
cp .env.example .env
nano .env  # Customize settings

# Deploy service
./deploy.sh
```

### Updating Services

```bash
# Update specific service
cd compositions/[category]/[service-name]
docker-compose pull && docker-compose up -d

# Update all services (planned automation)
# ./scripts/update-all.sh
```

### Backup Services

```bash
# Backup specific service
cd compositions/[category]/[service-name]
./backup.sh

# Backup all services (planned automation)
# ./scripts/backup-all.sh
```

### Monitoring and Maintenance

```bash
# Check all service status
docker ps

# View resource usage
docker stats

# Check service logs
cd compositions/[category]/[service-name]
docker-compose logs -f
```

## Adding New Services

When adding new services to this infrastructure:

1. **Follow Established Patterns**: Use the service template from [`docs/SERVICE_TEMPLATE.md`](../docs/SERVICE_TEMPLATE.md)
2. **Choose Appropriate Category**: Place in the correct `compositions/` subdirectory
3. **Include Complete Documentation**: Provide comprehensive README.md
4. **Use Standard Environment Variables**: Follow naming conventions
5. **Implement Security Best Practices**: Local access, resource limits, health checks
6. **Test Thoroughly**: Validate deployment, backup, and restore procedures

## Troubleshooting

### Common Issues

- **Permission Problems**: Check PUID/PGID settings and file ownership
- **Port Conflicts**: Verify port availability and firewall settings
- **Resource Issues**: Monitor memory and CPU usage
- **Storage Problems**: Check disk space and volume mounts

### Diagnostic Commands

```bash
# Check Docker daemon status
docker info

# View all containers
docker ps -a

# Check resource usage
docker system df
docker stats --no-stream

# View Docker logs
journalctl -u docker -f
```

## Security Considerations

### Network Security

- Services configured for local network access only
- Firewall rules restrict external access
- Custom networks isolate service communication

### Data Protection

- Regular backup procedures for all services
- Proper file permissions and ownership
- Encrypted storage recommendations for sensitive data

### Access Control

- Strong authentication requirements
- Role-based access where supported
- Regular security updates for container images

## Integration with Synology DSM

This Docker infrastructure is optimized for Synology NAS systems:

- **DSM Integration**: Compatible with Container Manager GUI
- **Volume Optimization**: Proper volume paths for Synology storage
- **Permission Handling**: Correct PUID/PGID for Synology users
- **Resource Management**: Appropriate limits for NAS hardware
- **Security Alignment**: Follows Synology security best practices

## Support and Documentation

### Project Documentation

- [Main Project README](../README.md)
- [Setup Guide](../docs/SETUP.md)
- [Security Best Practices](../docs/SECURITY.md)
- [Troubleshooting Guide](../docs/TROUBLESHOOTING.md)
- [Service Template](../docs/SERVICE_TEMPLATE.md)
- [Contributing Guidelines](../CONTRIBUTING.md)

### Service-Specific Documentation

Each service includes detailed documentation in its respective directory:

- **Installation Instructions**: Step-by-step deployment
- **Configuration Guide**: Environment variable explanations
- **Troubleshooting**: Service-specific issues and solutions
- **Advanced Usage**: Integration and customization options

---

**Docker Infrastructure Version**: 1.0  
**Last Updated**: 2024  
**Compatibility**: Synology DSM 7.2+, Docker 20.10+
