# Synology NAS Docker Management

A comprehensive Docker container management solution specifically designed for Synology NAS systems running DSM 7.2+. This project provides a structured approach to deploying, managing, and maintaining Docker services on your Synology NAS with focus on security, reliability, and ease of use.

## 🌟 Project Overview

This project offers a generalized framework that can be used by anyone with a Synology NAS to manage Docker containers efficiently. It emphasizes:

- **Security-First Approach**: Local network access only, proper permission management
- **Synology Optimization**: Tailored for DSM 7.2+ with proper volume mappings and permissions
- **Service Organization**: Structured directory layout for easy service management
- **Automated Deployment**: Scripts and templates for quick service deployment
- **Comprehensive Documentation**: Detailed guides for each service and common tasks

## 🚀 Quick Start

### Prerequisites

- **Synology NAS** with DSM 7.2 or later
- **Docker Package** installed (Container Manager in DSM 7.2)
- **SSH Access** to your NAS (recommended)
- **Basic Docker Knowledge** and Synology NAS administration experience

### 1. Project Setup

1. **Clone or download this project** to your Synology NAS:

   ```bash
   # SSH into your NAS
   ssh admin@your-nas-ip
   
   # Navigate to your docker directory
   cd /volume1/docker
   
   # Clone the project (or download and extract)
   git clone <repository-url> syno-nas
   cd syno-nas
   ```

2. **Set proper permissions**:

   ```bash
   # Make scripts executable
   chmod +x docker/scripts/*.sh
   chmod +x docker/compositions/*/deploy.sh
   ```

### 2. Deploy Portainer (Recommended First Service)

[Portainer](docker/compositions/management/portainer/) provides a web-based interface for managing all your Docker containers and is the recommended starting point:

```bash
# Navigate to Portainer service
cd docker/compositions/management/portainer

# Configure environment
cp .env.example .env
nano .env  # Edit with your settings

# Deploy Portainer
docker-compose up -d
```

**Access Portainer**: `http://your-nas-ip:9000`

For detailed Portainer setup instructions, see the [Portainer README](docker/compositions/management/portainer/README.md).

### 3. Explore Available Services

Browse the [`infra/docker/apps/`](infra/docker/apps/) directory to see available service stacks:

- **syno-core**: Core infrastructure services including SurrealDB, Portainer, and backup systems
- **Management**: Portainer, monitoring tools
- **Media**: Plex, Jellyfin, *arr services (coming soon)
- **Productivity**: NextCloud, collaboration tools (coming soon)
- **Networking**: VPN, proxy services (coming soon)

### 4. SurrealDB Backup System

The project includes a comprehensive SurrealDB backup solution:

- **[SurrealDB Backup System User Guide](SURREALDB_BACKUP_GUIDE.md)** - Complete usage and monitoring guide
- **[SurrealDB Backup Deployment Guide](SURREALDB_BACKUP_DEPLOYMENT.md)** - Initial setup and configuration

## 📁 Project Structure

```plaintext
syno-nas/
├── README.md                          # This file - main project documentation
├── CONTRIBUTING.md                    # Guide for adding new services
├── CHANGELOG.md                       # Project updates and version history
├── docker-compose.yml                 # Optional: Root compose file for basic services
│
├── docker/
│   ├── compositions/                  # Service definitions organized by category
│   │   ├── management/               # Docker management tools
│   │   │   └── portainer/           # Portainer container management UI
│   │   │       ├── README.md        # Detailed Portainer documentation
│   │   │       ├── docker-compose.yml
│   │   │       ├── .env.example     # Environment configuration template
│   │   │       ├── deploy.sh        # Automated deployment script
│   │   │       └── backup.sh        # Backup automation script
│   │   ├── media/                   # Media server services (planned)
│   │   ├── productivity/            # Productivity applications (planned)
│   │   └── networking/              # Network services (planned)
│   │
│   ├── dockerfiles/                  # Custom Docker images
│   │   └── README.md                # Custom image documentation
│   │
│   └── scripts/                      # Utility scripts
│       ├── README.md                # Script documentation
│       ├── backup-all.sh            # Backup all services (planned)
│       ├── update-all.sh            # Update all services (planned)
│       └── health-check.sh          # System health monitoring (planned)
│
└── docs/                             # Additional documentation
    ├── SETUP.md                     # Detailed setup guide
    ├── SECURITY.md                  # Security best practices
    └── TROUBLESHOOTING.md           # Common issues and solutions
```

## 🛠️ Service Management

### Adding New Services

1. **Choose appropriate category** in [`docker/compositions/`](docker/compositions/)
2. **Create service directory** following the established pattern
3. **Use the service template** (see [CONTRIBUTING.md](CONTRIBUTING.md))
4. **Document your service** with detailed README.md

### Service Deployment Patterns

Each service follows a consistent structure:

```plaintext
service-name/
├── README.md              # Comprehensive service documentation
├── docker-compose.yml     # Service definition
├── .env.example          # Environment template
├── deploy.sh             # Deployment automation
└── backup.sh             # Backup procedures
```

### Environment Management

- **Separate environments** for each service
- **Template files** (`.env.example`) with documentation
- **Security-focused defaults** for Synology NAS
- **Consistent variable naming** across services

## 📖 Documentation

### Service-Specific Documentation

Each service includes comprehensive documentation:

- **[Portainer](docker/compositions/management/portainer/README.md)**: Docker container management UI
- More services coming soon...

### General Guides

- **[Project Setup Guide](docs/SETUP.md)**: Detailed installation and configuration
- **[Security Best Practices](docs/SECURITY.md)**: Securing your Docker environment
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)**: Common issues and solutions
- **[Contributing Guide](CONTRIBUTING.md)**: Adding new services to the project

## 🔧 Management Tools

### Portainer Web Interface

The primary management interface accessible at `http://your-nas-ip:9000`:

- **Container Management**: Start, stop, restart, and monitor containers
- **Image Management**: Pull, build, and manage Docker images
- **Volume Management**: Create and manage persistent storage
- **Network Management**: Configure container networking
- **System Monitoring**: Resource usage and performance metrics

### Command Line Tools

Useful commands for managing your Docker environment:

```bash
# View all running containers
docker ps

# Check container logs
docker-compose logs -f service-name

# Update a service
cd docker/compositions/category/service-name
docker-compose pull && docker-compose up -d

# Backup service data
./backup.sh

# Deploy a new service
./deploy.sh
```

## 🔒 Security Considerations

### Network Security

- **Local Network Only**: Services configured for local access by default
- **No External Exposure**: Avoid exposing management interfaces to the internet
- **Firewall Configuration**: Use DSM firewall to control access
- **SSL/TLS**: Implement HTTPS for sensitive services

### Data Protection

- **Regular Backups**: Automated backup scripts for each service
- **Permission Management**: Proper user and group ID configuration
- **Volume Security**: Secure volume mappings and access controls
- **Update Management**: Regular security updates for containers

### Access Control

- **Strong Authentication**: Use complex passwords and consider 2FA
- **User Separation**: Separate users for different service categories
- **Audit Logging**: Enable logging for security monitoring
- **Resource Limits**: Prevent resource exhaustion attacks

## 🚨 Troubleshooting

### Common Issues

#### Port Conflicts

```bash
# Check what's using a port
sudo netstat -tlnp | grep :PORT_NUMBER

# Solution: Change port in service .env file
```

#### Permission Problems

```bash
# Fix ownership (replace with your PUID:PGID)
sudo chown -R 1000:1000 /path/to/service/data
sudo chmod -R 755 /path/to/service/data
```

#### Container Not Starting

```bash
# Check container logs
docker-compose logs service-name

# Check system resources
docker stats

# Verify configuration
docker-compose config
```

### Getting Help

1. **Check service-specific README** for detailed troubleshooting
2. **Review logs** for error messages and diagnostic information
3. **Verify configuration** files and environment variables
4. **Check system resources** and available storage space
5. **Consult community forums** for Synology and Docker support

## 📋 Maintenance

### Regular Tasks

- **Monitor resource usage** through Portainer dashboard
- **Update container images** regularly for security patches
- **Backup service data** according to your backup schedule
- **Review logs** for errors or security issues
- **Check disk space** and clean up unused images/containers

### Update Procedures

```bash
# Update all services (planned automation)
./docker/scripts/update-all.sh

# Update specific service
cd docker/compositions/category/service-name
docker-compose pull && docker-compose up -d

# Clean up unused resources
docker system prune -a
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:

- Adding new service definitions
- Improving existing documentation
- Reporting issues and bugs
- Suggesting enhancements
- Sharing security improvements

### Adding a New Service

1. Follow the established directory structure
2. Use the service template for consistency
3. Include comprehensive documentation
4. Test on Synology DSM 7.2+
5. Submit a pull request with detailed description

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed version history and updates.

## 📞 Support

### Project Resources

- **Documentation**: Comprehensive guides in each service directory
- **Issues**: Report problems and feature requests in project issues
- **Discussions**: Community discussions and Q&A

### External Resources

- [Synology Community](https://community.synology.com/)
- [Docker Documentation](https://docs.docker.com/)
- [Portainer Documentation](https://docs.portainer.io/)

---

**Project Status**: Active Development  
**Version**: 1.0.0  
**Last Updated**: 2024  
**Compatibility**: Synology DSM 7.2+, Docker 20.10+

**License**: MIT License - feel free to use, modify, and distribute according to your needs.
