# Security Best Practices for Synology NAS Docker Management

This guide provides comprehensive security recommendations for running Docker containers on your Synology NAS, ensuring your services are protected against common threats while maintaining usability.

## Table of Contents

- [Security Philosophy](#security-philosophy)
- [Network Security](#network-security)
- [Container Security](#container-security)
- [Data Protection](#data-protection)
- [Access Control](#access-control)
- [Monitoring and Auditing](#monitoring-and-auditing)
- [Backup Security](#backup-security)
- [Update Management](#update-management)
- [Incident Response](#incident-response)

## Security Philosophy

### Defense in Depth

Implement multiple layers of security:

1. **Network Perimeter**: Firewalls and network isolation
2. **Host Security**: Synology DSM hardening
3. **Container Security**: Isolation and resource limits
4. **Application Security**: Service-specific protections
5. **Data Security**: Encryption and access controls

### Principle of Least Privilege

- Grant minimum necessary permissions
- Use dedicated service accounts
- Implement role-based access control
- Regular permission audits

### Security by Default

- Local network access only by default
- Strong default configurations
- Automatic security updates where possible
- Secure credential management

## Network Security

### Firewall Configuration

#### DSM Firewall Setup

1. **Enable DSM Firewall**:
   ```
   Control Panel → Security → Firewall → Enable firewall
   ```

2. **Create Service-Specific Rules**:
   ```
   Rule Name: Docker Management
   Ports: 9000 (Portainer)
   Source IP: Local network only (192.168.1.0/24)
   Action: Allow
   ```

3. **Default Deny Policy**:
   ```
   Create rule: All ports → All sources → Deny (lowest priority)
   ```

#### Advanced Firewall Rules

```bash
# Example iptables rules for additional protection
sudo iptables -A INPUT -p tcp --dport 9000 -s 192.168.1.0/24 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9000 -j DROP

# Save rules
sudo iptables-save > /etc/iptables/rules.v4
```

### Network Isolation

#### Docker Networks

```yaml
# Use custom networks for service isolation
networks:
  frontend:
    driver: bridge
    internal: false  # Internet access allowed
  backend:
    driver: bridge
    internal: true   # No internet access
```

#### Service Network Configuration

```yaml
services:
  web-service:
    networks:
      - frontend
  database:
    networks:
      - backend  # Isolated from internet
```

### VPN Access

#### Remote Access Security

For secure remote access:

1. **Use Synology VPN Server**:
   - Install VPN Server package
   - Configure OpenVPN or L2TP/IPSec
   - Use certificate-based authentication

2. **Alternative: WireGuard**:
   ```yaml
   # Deploy WireGuard container for secure access
   services:
     wireguard:
       image: linuxserver/wireguard
       container_name: wireguard
       cap_add:
         - NET_ADMIN
         - SYS_MODULE
   ```

### Port Management

#### Recommended Port Ranges

```env
# Management services: 9000-9099
PORTAINER_PORT=9000
MONITORING_PORT=9001

# Media services: 8000-8099
PLEX_PORT=8096
JELLYFIN_PORT=8097

# Productivity: 7000-7099
NEXTCLOUD_PORT=7080
```

#### Port Scanning Protection

```bash
# Install and configure fail2ban
sudo apt install fail2ban

# Configure for SSH protection
cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
```

## Container Security

### Resource Limits

#### Memory and CPU Limits

```yaml
services:
  portainer:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.25'
```

#### Disk I/O Limits

```yaml
services:
  service-name:
    blkio_config:
      weight: 300
      device_read_bps:
        - path: /dev/sda
          rate: '50mb'
```

### Container Isolation

#### User Namespace Mapping

```yaml
services:
  secure-service:
    user: "1000:1000"  # Non-root user
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
      - /var/tmp
```

#### Capability Management

```yaml
services:
  limited-service:
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
```

#### Security Options

```yaml
services:
  hardened-service:
    security_opt:
      - no-new-privileges:true
      - seccomp:unconfined  # Only if absolutely necessary
    read_only: true
    volumes:
      - type: tmpfs
        target: /tmp
        tmpfs:
          size: 100M
```

### Image Security

#### Trusted Image Sources

```yaml
# Use official images or trusted repositories
services:
  portainer:
    image: portainer/portainer-ce:lts  # Official image
    # Avoid: untrusted/random-image:latest
```

#### Image Scanning

```bash
# Scan images for vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image portainer/portainer-ce:lts

# Regular security updates
docker-compose pull && docker-compose up -d
```

#### Image Verification

```bash
# Enable Docker Content Trust
export DOCKER_CONTENT_TRUST=1

# Verify image signatures
docker trust inspect portainer/portainer-ce:lts
```

## Data Protection

### Volume Security

#### Secure Volume Mounts

```yaml
volumes:
  # Read-only mounts where possible
  - ./config:/app/config:ro
  
  # Specific paths, not entire volumes
  - ./data/app:/app/data
  # Avoid: /volume1:/data (too broad)
```

#### Volume Permissions

```bash
# Set restrictive permissions
chmod 750 /volume1/docker/data
chown root:docker /volume1/docker/data

# Service-specific permissions
chmod 700 /volume1/docker/secure-service/data
chown 1000:1000 /volume1/docker/secure-service/data
```

### Encryption

#### Data at Rest

```bash
# Use encrypted volumes for sensitive data
cryptsetup luksFormat /dev/sdX
cryptsetup luksOpen /dev/sdX encrypted_volume
mkfs.ext4 /dev/mapper/encrypted_volume
```

#### Data in Transit

```yaml
services:
  secure-web:
    environment:
      - SSL_CERT_PATH=/certs/server.crt
      - SSL_KEY_PATH=/certs/server.key
    volumes:
      - ./certs:/certs:ro
```

### Secrets Management

#### Docker Secrets

```yaml
services:
  app:
    secrets:
      - db_password
      - api_key

secrets:
  db_password:
    file: ./secrets/db_password.txt
  api_key:
    external: true
```

#### Environment Variable Security

```bash
# Never store secrets in .env files in version control
echo ".env" >> .gitignore
echo "secrets/" >> .gitignore

# Use secure file permissions for .env files
chmod 600 .env
chown root:docker .env
```

## Access Control

### Authentication

#### Strong Password Policies

- **Minimum Length**: 12 characters
- **Complexity**: Upper, lower, numbers, symbols
- **No Dictionary Words**: Avoid common passwords
- **Regular Rotation**: Change every 90 days

#### Multi-Factor Authentication

Enable 2FA where supported:

```yaml
# Example: Authelia for centralized auth
services:
  authelia:
    image: authelia/authelia:latest
    environment:
      - AUTHELIA_JWT_SECRET_FILE=/secrets/jwt
      - AUTHELIA_SESSION_SECRET_FILE=/secrets/session
```

### Authorization

#### Role-Based Access Control

```yaml
# Portainer role configuration example
users:
  - name: "admin"
    role: "administrator"
  - name: "operator"
    role: "operator"
    endpoints: ["local"]
  - name: "readonly"
    role: "readonly"
```

#### Service-Specific Permissions

```env
# Environment-based access control
ADMIN_USERS=admin,superuser
READONLY_USERS=viewer,guest
ALLOWED_IPS=192.168.1.0/24,10.0.0.0/8
```

### SSH Security

#### SSH Hardening

```bash
# Edit SSH configuration
sudo nano /etc/ssh/sshd_config

# Recommended settings:
Port 2222                    # Non-standard port
PermitRootLogin no          # Disable root login
PasswordAuthentication no   # Use key-based auth
MaxAuthTries 3             # Limit auth attempts
ClientAliveInterval 300    # Session timeout
```

#### SSH Key Management

```bash
# Generate strong SSH key
ssh-keygen -t ed25519 -b 4096 -f ~/.ssh/synology_key

# Copy to NAS
ssh-copy-id -i ~/.ssh/synology_key.pub admin@nas-ip

# Disable password auth after key setup
```

## Monitoring and Auditing

### Log Management

#### Centralized Logging

```yaml
services:
  app:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        labels: "service,version"
```

#### Security Event Monitoring

```bash
# Monitor authentication logs
tail -f /var/log/auth.log | grep "authentication failure"

# Monitor Docker events
docker events --filter type=container --filter event=start
```

### Intrusion Detection

#### File Integrity Monitoring

```bash
# Install and configure AIDE
sudo apt install aide
sudo aideinit

# Daily integrity checks
echo "0 2 * * * /usr/bin/aide --check" | sudo crontab -
```

#### Network Monitoring

```bash
# Monitor network connections
netstat -tulpn | grep LISTEN

# Monitor for suspicious network activity
sudo tcpdump -i any -n host suspicious-ip
```

### Health Monitoring

#### Container Health Checks

```yaml
services:
  monitored-service:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

#### System Resource Monitoring

```bash
# Monitor system resources
docker stats --no-stream
df -h
free -h

# Set up alerts for resource exhaustion
```

## Backup Security

### Backup Encryption

```bash
# Encrypted backup script
#!/bin/bash
BACKUP_DIR="/volume1/backups"
DATE=$(date +%Y%m%d_%H%M%S)
PASSPHRASE_FILE="/secure/backup.key"

# Create encrypted backup
tar -czf - /volume1/docker/data | \
gpg --cipher-algo AES256 --compress-algo 1 --symmetric \
    --passphrase-file "$PASSPHRASE_FILE" \
    --output "$BACKUP_DIR/backup_$DATE.tar.gz.gpg"
```

### Backup Verification

```bash
# Verify backup integrity
#!/bin/bash
BACKUP_FILE="$1"
TEMP_DIR="/tmp/backup_verify"

# Decrypt and verify
gpg --decrypt "$BACKUP_FILE" | tar -tzf - > /dev/null
if [ $? -eq 0 ]; then
    echo "Backup verification successful"
else
    echo "Backup verification failed"
fi
```

### Offsite Backup Security

```bash
# Secure offsite sync
rsync -avz --delete --encrypt \
    /volume1/backups/ \
    backup-user@remote-server:/secure/backups/
```

## Update Management

### Automated Updates

#### Container Updates

```bash
#!/bin/bash
# Automated update script with security focus

# Pull latest images
docker-compose pull

# Update containers
docker-compose up -d

# Clean up old images
docker image prune -f

# Log update activity
echo "$(date): Containers updated" >> /var/log/docker-updates.log
```

#### Security Update Schedule

```bash
# Cron job for security updates
0 2 * * 1 /opt/scripts/security-updates.sh  # Weekly Monday 2 AM
0 3 1 * * /opt/scripts/full-updates.sh      # Monthly 1st day 3 AM
```

### Vulnerability Management

#### Regular Scanning

```bash
# Vulnerability scanning script
#!/bin/bash
SCAN_LOG="/var/log/vuln-scan.log"

# Scan all running containers
for container in $(docker ps --format "{{.Names}}"); do
    echo "Scanning $container..." | tee -a $SCAN_LOG
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
        aquasec/trivy image $(docker inspect --format='{{.Config.Image}}' $container) \
        | tee -a $SCAN_LOG
done
```

#### Update Notifications

```bash
# Email notification for critical updates
#!/bin/bash
CRITICAL_VULNS=$(grep "CRITICAL" /var/log/vuln-scan.log | wc -l)

if [ $CRITICAL_VULNS -gt 0 ]; then
    echo "Critical vulnerabilities found: $CRITICAL_VULNS" | \
    mail -s "Security Alert: Critical Vulnerabilities" admin@example.com
fi
```

## Incident Response

### Security Incident Procedures

#### Immediate Response

1. **Isolate Affected Systems**:
   ```bash
   # Stop compromised containers
   docker-compose down
   
   # Isolate network segments
   docker network disconnect bridge container-name
   ```

2. **Preserve Evidence**:
   ```bash
   # Capture container state
   docker commit compromised-container evidence-image
   
   # Export logs
   docker logs compromised-container > incident-logs.txt
   ```

3. **Assess Damage**:
   ```bash
   # Check file integrity
   aide --check
   
   # Review access logs
   grep "failed\|error\|unauthorized" /var/log/auth.log
   ```

#### Recovery Procedures

1. **Clean Recovery**:
   ```bash
   # Remove compromised containers
   docker-compose down
   docker system prune -a
   
   # Restore from clean backup
   tar -xzf clean-backup.tar.gz
   ```

2. **Security Hardening**:
   ```bash
   # Update all components
   docker-compose pull
   
   # Implement additional security measures
   # Change all passwords
   # Review firewall rules
   # Update security configurations
   ```

### Documentation

#### Incident Report Template

```markdown
# Security Incident Report

**Date**: YYYY-MM-DD HH:MM:SS
**Severity**: Critical/High/Medium/Low
**Affected Systems**: List systems
**Reporter**: Name and contact

## Summary
Brief description of the incident

## Timeline
- HH:MM - Initial detection
- HH:MM - Response initiated
- HH:MM - Containment achieved
- HH:MM - Recovery completed

## Impact Assessment
Description of affected services and data

## Root Cause Analysis
Technical details of how the incident occurred

## Remediation Actions
Steps taken to resolve the incident

## Preventive Measures
Changes implemented to prevent recurrence

## Lessons Learned
Key takeaways and process improvements
```

## Security Checklist

### Daily Security Tasks

- [ ] Review system logs for anomalies
- [ ] Check container health status
- [ ] Verify backup completion
- [ ] Monitor resource usage
- [ ] Check for failed login attempts

### Weekly Security Tasks

- [ ] Update container images
- [ ] Review firewall logs
- [ ] Check for security advisories
- [ ] Verify backup integrity
- [ ] Review user access logs

### Monthly Security Tasks

- [ ] Full vulnerability scan
- [ ] Review and update passwords
- [ ] Audit user permissions
- [ ] Test incident response procedures
- [ ] Review security configurations

### Quarterly Security Tasks

- [ ] Comprehensive security audit
- [ ] Penetration testing
- [ ] Review and update security policies
- [ ] Security awareness training
- [ ] Disaster recovery testing

## Emergency Contacts

### Internal Contacts

- **Primary Administrator**: [Contact Information]
- **Backup Administrator**: [Contact Information]
- **Security Team**: [Contact Information]

### External Resources

- **Synology Support**: [Support Information]
- **Security Vendor Support**: [Contact Information]
- **Emergency Response Team**: [Contact Information]

---

**Security Guide Version**: 1.0  
**Last Updated**: 2024  
**Review Schedule**: Quarterly  
**Next Review**: [Date]

**Remember**: Security is an ongoing process, not a one-time setup. Regular reviews and updates are essential for maintaining a secure environment.