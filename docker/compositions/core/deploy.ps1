#Requires -Version 5.1

<#
.SYNOPSIS
    Unified Core Services Deployment Script for Windows
    
.DESCRIPTION
    Automated deployment script for unified core services stack including
    Portainer (container management), SurrealDB (database), and Doppler (secrets).
    
    Windows PowerShell version of the Linux deployment script.
    
.PARAMETER Verbose
    Enable verbose output for detailed logging
    
.PARAMETER DryRun
    Show what would be done without executing commands
    
.PARAMETER Force
    Force deployment even if services are running
    
.PARAMETER SkipBackup
    Skip backup creation before deployment
    
.PARAMETER AutoConfirm
    Auto-confirm all prompts (useful for automation)
    
.PARAMETER Help
    Show help information
    
.EXAMPLE
    .\deploy.ps1
    Standard deployment with prompts
    
.EXAMPLE
    .\deploy.ps1 -Verbose
    Verbose deployment with detailed logging
    
.EXAMPLE
    .\deploy.ps1 -DryRun
    Show what would happen without executing
    
.EXAMPLE
    .\deploy.ps1 -Force -AutoConfirm
    Force deployment with auto-confirm
    
.NOTES
    Author: Synology NAS Core Services Team
    Version: 1.0.0
    Requires: Docker Desktop for Windows, PowerShell 5.1+
    
.LINK
    https://github.com/your-repo/syno-nas/docker/compositions/core
#>

[CmdletBinding()]
param(
    [switch]$Verbose,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$SkipBackup,
    [switch]$AutoConfirm,
    [switch]$Help
)

# Script configuration
$Script:ProjectName = "core-services"
$Script:ScriptDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$Script:LogFile = Join-Path $Script:ScriptDir "deployment.log"
$Script:BackupDir = "C:\DockerBackups\core"
$Script:RollbackStateFile = Join-Path $Script:ScriptDir ".rollback_state.json"

# Global variables
$Script:VerboseEnabled = $Verbose -or $VerbosePreference -eq 'Continue'
$Script:ErrorActionPreference = 'Stop'

# Color output functions
function Write-ColorOutput {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warn', 'Error', 'Debug', 'Step', 'Success')]
        [string]$Type = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$Type] $timestamp - $Message"
    
    # Write to log file
    Add-Content -Path $Script:LogFile -Value $logMessage -Encoding UTF8
    
    # Write to console with colors
    switch ($Type) {
        'Info'    { Write-Host "[INFO] " -ForegroundColor Green -NoNewline; Write-Host $Message }
        'Warn'    { Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
        'Error'   { Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $Message }
        'Debug'   { if ($Script:VerboseEnabled) { Write-Host "[DEBUG] " -ForegroundColor Blue -NoNewline; Write-Host $Message } }
        'Step'    { Write-Host "[STEP] " -ForegroundColor Magenta -NoNewline; Write-Host $Message }
        'Success' { Write-Host "[SUCCESS] " -ForegroundColor Green -NoNewline; Write-Host $Message }
    }
}

# Error handling
function Set-ErrorHandler {
    trap {
        Write-ColorOutput "Script failed with error: $($_.Exception.Message)" -Type Error
        Write-ColorOutput "At line: $($_.InvocationInfo.ScriptLineNumber)" -Type Error
        
        if (Test-Path $Script:RollbackStateFile) {
            Write-ColorOutput "Attempting automatic rollback..." -Type Warn
            Invoke-Rollback
        }
        
        Invoke-Cleanup
        throw $_
    }
}

# Cleanup function
function Invoke-Cleanup {
    Write-ColorOutput "Performing cleanup operations..." -Type Debug
    
    # Remove temporary files if any
    $tempBackup = "$env:TEMP\core-services-backup.zip"
    if (Test-Path $tempBackup) {
        Remove-Item $tempBackup -Force -ErrorAction SilentlyContinue
    }
}

# Help function
function Show-Help {
    $helpText = @"
Unified Core Services Deployment Script

DESCRIPTION:
    Automated deployment script for unified core services stack including
    Portainer (container management), SurrealDB (database), and Doppler (secrets).
    
    Windows PowerShell version optimized for Docker Desktop.

USAGE:
    .\deploy.ps1 [OPTIONS]

OPTIONS:
    -Verbose         Enable verbose output for detailed logging
    -DryRun          Show what would be done without executing commands
    -Force           Force deployment even if services are running
    -SkipBackup      Skip backup creation before deployment
    -AutoConfirm     Auto-confirm all prompts (useful for automation)
    -Help            Show this help information

EXAMPLES:
    .\deploy.ps1                    # Standard deployment with prompts
    .\deploy.ps1 -Verbose           # Verbose deployment with detailed logging
    .\deploy.ps1 -DryRun            # Show what would happen without executing
    .\deploy.ps1 -Force -AutoConfirm # Force deployment with auto-confirm

PREREQUISITES:
    • Docker Desktop for Windows
    • PowerShell 5.1 or later
    • Minimum 2GB available RAM
    • 1GB free storage space
    • Valid Doppler account and service token

FILES CREATED/MODIFIED:
    • C:\DockerData\core\          (Service data directories)
    • C:\DockerBackups\core\       (Backup storage)
    • .\deployment.log             (Deployment log)
    • .\.env                       (Environment configuration)

For more information, see README.md
"@
    
    Write-Host $helpText -ForegroundColor Cyan
}

# System requirements check
function Test-SystemRequirements {
    Write-ColorOutput "Step 1: Checking system requirements..." -Type Step
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    Write-ColorOutput "PowerShell version: $psVersion" -Type Debug
    
    if ($psVersion.Major -lt 5) {
        Write-ColorOutput "PowerShell 5.1 or later is required. Current version: $psVersion" -Type Error
        throw "Insufficient PowerShell version"
    }
    
    # Check Docker Desktop
    try {
        $dockerVersion = docker --version
        Write-ColorOutput "Docker version: $dockerVersion" -Type Debug
        
        # Test Docker daemon
        docker info | Out-Null
        Write-ColorOutput "Docker daemon is running" -Type Debug
    }
    catch {
        Write-ColorOutput "Docker is not installed or not running. Please install Docker Desktop and ensure it's running." -Type Error
        throw "Docker not available"
    }
    
    # Check Docker Compose
    try {
        $composeVersion = docker-compose --version
        Write-ColorOutput "Docker Compose version: $composeVersion" -Type Debug
    }
    catch {
        Write-ColorOutput "Docker Compose is not available." -Type Error
        throw "Docker Compose not available"
    }
    
    # Check available memory (approximate)
    $memory = Get-CimInstance -ClassName Win32_OperatingSystem
    $availableMemoryMB = [math]::Round($memory.FreePhysicalMemory / 1024)
    
    if ($availableMemoryMB -lt 2048) {
        Write-ColorOutput "Available memory ($availableMemoryMB MB) is less than recommended 2GB" -Type Warn
        if (-not $Force -and -not $AutoConfirm) {
            $continue = Read-Host "Continue anyway? (y/N)"
            if ($continue -notmatch '^[Yy]$') {
                throw "Insufficient memory"
            }
        }
    }
    
    # Check available disk space
    $drive = Get-PSDrive C
    $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
    
    if ($freeSpaceGB -lt 1) {
        Write-ColorOutput "Available disk space ($freeSpaceGB GB) is less than recommended 1GB" -Type Warn
        if (-not $Force -and -not $AutoConfirm) {
            $continue = Read-Host "Continue anyway? (y/N)"
            if ($continue -notmatch '^[Yy]$') {
                throw "Insufficient disk space"
            }
        }
    }
    
    Write-ColorOutput "System requirements check completed successfully" -Type Success
}

# Configuration validation
function Test-Configuration {
    Write-ColorOutput "Step 2: Validating configuration files..." -Type Step
    
    $envFile = Join-Path $Script:ScriptDir ".env"
    $envExample = Join-Path $Script:ScriptDir ".env.example"
    
    # Check if .env file exists
    if (-not (Test-Path $envFile)) {
        Write-ColorOutput ".env file not found. Creating from template..." -Type Warn
        
        if (Test-Path $envExample) {
            if (-not $DryRun) {
                Copy-Item $envExample $envFile
                Write-ColorOutput "Created .env file from template. Please review and update configuration." -Type Info
                
                if (-not $AutoConfirm) {
                    Read-Host "Press Enter to continue after reviewing .env file..."
                }
            }
        }
        else {
            Write-ColorOutput ".env.example template not found. Cannot create configuration." -Type Error
            throw "Configuration template missing"
        }
    }
    
    # Load environment variables
    if (Test-Path $envFile) {
        Write-ColorOutput "Loading environment variables from .env file..." -Type Debug
        
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$' -and -not $_.StartsWith('#')) {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                [Environment]::SetEnvironmentVariable($name, $value, 'Process')
                Write-ColorOutput "Set environment variable: $name" -Type Debug
            }
        }
    }
    
    # Validate critical environment variables
    $requiredVars = @(
        'DOPPLER_TOKEN',
        'DOPPLER_PROJECT', 
        'PORTAINER_PORT',
        'SURREALDB_PORT',
        'PUID',
        'PGID'
    )
    
    foreach ($var in $requiredVars) {
        $value = [Environment]::GetEnvironmentVariable($var, 'Process')
        if ([string]::IsNullOrEmpty($value)) {
            Write-ColorOutput "Required environment variable '$var' is not set in .env file" -Type Error
            throw "Missing environment variable: $var"
        }
        Write-ColorOutput "✓ $var is set" -Type Debug
    }
    
    # Validate Doppler token format
    $dopplerToken = [Environment]::GetEnvironmentVariable('DOPPLER_TOKEN', 'Process')
    if ($dopplerToken -notmatch '^dp\.pt\.') {
        Write-ColorOutput "DOPPLER_TOKEN format appears invalid (should start with 'dp.pt.')" -Type Error
        throw "Invalid Doppler token format"
    }
    
    # Check port conflicts
    $portainerPort = [Environment]::GetEnvironmentVariable('PORTAINER_PORT', 'Process')
    $surrealdbPort = [Environment]::GetEnvironmentVariable('SURREALDB_PORT', 'Process')
    $edgePort = [Environment]::GetEnvironmentVariable('PORTAINER_EDGE_PORT', 'Process')
    
    $ports = @($portainerPort, $surrealdbPort, $edgePort) | Where-Object { $_ }
    
    foreach ($port in $ports) {
        $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($connections) {
            Write-ColorOutput "Port $port is already in use" -Type Warn
            if (-not $Force -and -not $AutoConfirm) {
                $continue = Read-Host "Continue anyway? (y/N)"
                if ($continue -notmatch '^[Yy]$') {
                    throw "Port conflict on port $port"
                }
            }
        }
    }
    
    Write-ColorOutput "Configuration validation completed successfully" -Type Success
}

# Directory structure creation
function New-DirectoryStructure {
    Write-ColorOutput "Step 3: Creating directory structure..." -Type Step
    
    # Note: PUID/PGID are Linux-specific concepts for user/group ownership
    # On Windows, we use ACL-based permissions instead
    Write-ColorOutput "Creating directories with Windows ACL permissions..." -Type Debug
    
    $directories = @(
        'C:\DockerData\core',
        'C:\DockerData\core\portainer\data',
        'C:\DockerData\core\surrealdb\data',
        'C:\DockerData\core\surrealdb\config',
        'C:\DockerData\core\doppler',
        'C:\DockerBackups\core'
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            Write-ColorOutput "Creating directory: $dir" -Type Debug
            if (-not $DryRun) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                
                # Set permissions (Windows equivalent)
                try {
                    $acl = Get-Acl $dir
                    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                        'FullControl',
                        'ContainerInherit,ObjectInherit',
                        'None',
                        'Allow'
                    )
                    $acl.SetAccessRule($accessRule)
                    Set-Acl -Path $dir -AclObject $acl
                }
                catch {
                    Write-ColorOutput "Warning: Could not set permissions on $dir" -Type Warn
                }
            }
        }
        else {
            Write-ColorOutput "Directory already exists: $dir" -Type Debug
        }
    }
    
    Write-ColorOutput "Directory structure created successfully" -Type Success
}

# Rollback state management
function Save-RollbackState {
    Write-ColorOutput "Saving rollback state..." -Type Debug
    
    if (-not $DryRun) {
        $containers = docker ps --format "{{.Names}}" | Where-Object { $_ -match "(portainer|surrealdb|doppler)" }
        $networks = docker network ls --format "{{.Name}}" | Where-Object { $_ -match "core" }
        
        $rollbackData = @{
            ContainersBeforeDeploy = $containers -join ' '
            NetworksBeforeDeploy = $networks -join ' '
            DeploymentTimestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            BackupCreated = -not $SkipBackup
        }
        
        $rollbackData | ConvertTo-Json | Set-Content $Script:RollbackStateFile -Encoding UTF8
    }
}

# Rollback functionality
function Invoke-Rollback {
    Write-ColorOutput "Performing rollback to previous state..." -Type Warn
    
    if (-not (Test-Path $Script:RollbackStateFile)) {
        Write-ColorOutput "No rollback state found. Manual cleanup may be required." -Type Error
        return
    }
    
    try {
        $rollbackData = Get-Content $Script:RollbackStateFile -Encoding UTF8 | ConvertFrom-Json
        
        Write-ColorOutput "Rollback initiated from deployment at $(Get-Date -Date ([DateTimeOffset]::FromUnixTimeSeconds($rollbackData.DeploymentTimestamp)))" -Type Debug
        
        # Stop and remove new containers
        Write-ColorOutput "Stopping and removing containers..." -Type Debug
        docker-compose down --remove-orphans 2>$null
        
        # Remove networks created during deployment
        Write-ColorOutput "Cleaning up networks..." -Type Debug
        docker network rm core-network 2>$null
        
        # Log rollback details for audit
        Write-ColorOutput "Rollback details: Backup was $(if ($rollbackData.BackupCreated) { 'created' } else { 'skipped' })" -Type Debug
        
        Write-ColorOutput "Rollback completed. Please check system state manually." -Type Info
        Remove-Item $Script:RollbackStateFile -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-ColorOutput "Rollback failed: $($_.Exception.Message)" -Type Error
    }
}

# Backup creation
function New-Backup {
    if ($SkipBackup) {
        Write-ColorOutput "Skipping backup creation as requested" -Type Debug
        return
    }
    
    Write-ColorOutput "Step 4: Creating backup of existing data..." -Type Step
    
    $backupTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $Script:BackupDir $backupTimestamp
    
    if (-not $DryRun) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        
        # Backup existing data if present
        $portainerData = 'C:\DockerData\core\portainer\data'
        if (Test-Path $portainerData) {
            $items = Get-ChildItem $portainerData -ErrorAction SilentlyContinue
            if ($items) {
                Write-ColorOutput "Backing up Portainer data..." -Type Debug
                $backupFile = Join-Path $backupDir "portainer-backup.zip"
                Compress-Archive -Path "$portainerData\*" -DestinationPath $backupFile -ErrorAction SilentlyContinue
            }
        }
        
        $surrealdbData = 'C:\DockerData\core\surrealdb\data'
        if (Test-Path $surrealdbData) {
            $items = Get-ChildItem $surrealdbData -ErrorAction SilentlyContinue
            if ($items) {
                Write-ColorOutput "Backing up SurrealDB data..." -Type Debug
                $backupFile = Join-Path $backupDir "surrealdb-backup.zip"
                Compress-Archive -Path "$surrealdbData\*" -DestinationPath $backupFile -ErrorAction SilentlyContinue
            }
        }
        
        # Backup current configuration
        $envFile = Join-Path $Script:ScriptDir '.env'
        if (Test-Path $envFile) {
            Copy-Item $envFile (Join-Path $backupDir 'env-backup') -ErrorAction SilentlyContinue
        }
        
        # Backup docker-compose.yml
        $composeFile = Join-Path $Script:ScriptDir 'docker-compose.yml'
        if (Test-Path $composeFile) {
            Copy-Item $composeFile (Join-Path $backupDir 'docker-compose-backup.yml') -ErrorAction SilentlyContinue
        }
        
        Write-ColorOutput "Backup created at: $backupDir" -Type Success
    }
}

# Doppler connectivity test
function Test-DopplerConnectivity {
    Write-ColorOutput "Step 5: Testing Doppler connectivity..." -Type Step
    
    # Test Doppler authentication if CLI is available
    try {
        $dopplerToken = [Environment]::GetEnvironmentVariable('DOPPLER_TOKEN', 'Process')
        $env:DOPPLER_TOKEN = $dopplerToken
        
        $null = doppler me 2>$null
        Write-ColorOutput "✓ Doppler authentication successful" -Type Debug
    }
    catch {
        Write-ColorOutput "Doppler CLI not available or authentication failed. Will test via container." -Type Debug
    }
    
    Write-ColorOutput "Doppler connectivity test completed" -Type Success
}

# Build and deploy services
function Start-Deployment {
    Write-ColorOutput "Step 6: Building and deploying services..." -Type Step
    
    # Save current state for potential rollback
    Save-RollbackState
    
    if ($DryRun) {
        Write-ColorOutput "DRY RUN: Would execute: docker-compose up -d --build" -Type Info
        return
    }
    
    # Pull latest images
    Write-ColorOutput "Pulling latest images..." -Type Debug
    docker-compose pull 2>&1 | Tee-Object -FilePath $Script:LogFile -Append
    
    # Build custom images (Doppler)
    Write-ColorOutput "Building custom images..." -Type Debug
    docker-compose build 2>&1 | Tee-Object -FilePath $Script:LogFile -Append
    
    # Deploy services
    Write-ColorOutput "Starting services..." -Type Debug
    docker-compose up -d 2>&1 | Tee-Object -FilePath $Script:LogFile -Append
    
    Write-ColorOutput "Services deployment initiated" -Type Success
}

# Deployment verification
function Test-Deployment {
    Write-ColorOutput "Step 7: Verifying deployment..." -Type Step
    
    if ($DryRun) {
        Write-ColorOutput "DRY RUN: Would verify service health and connectivity" -Type Info
        return
    }
    
    # Wait for services to start
    Write-ColorOutput "Waiting for services to initialize..." -Type Debug
    Start-Sleep -Seconds 30
    
    # Check container status
    $containers = @('core-doppler', 'core-surrealdb', 'core-portainer')
    $allHealthy = $true
    
    foreach ($container in $containers) {
        $runningContainers = docker ps --format "{{.Names}}"
        if ($runningContainers -contains $container) {
            Write-ColorOutput "✓ Container $container is running" -Type Debug
            
            # Check health status if available
            try {
                $healthStatus = docker inspect --format='{{.State.Health.Status}}' $container 2>$null
                if ($healthStatus -eq 'healthy') {
                    Write-ColorOutput "✓ Container $container is healthy" -Type Debug
                }
                elseif ($healthStatus -eq 'starting') {
                    Write-ColorOutput "⚠ Container $container is still starting..." -Type Debug
                    Start-Sleep -Seconds 10
                }
                elseif ($healthStatus -and $healthStatus -ne 'no-healthcheck') {
                    Write-ColorOutput "Container $container health status: $healthStatus" -Type Warn
                    $allHealthy = $false
                }
            }
            catch {
                Write-ColorOutput "Could not check health for $container" -Type Debug
            }
        }
        else {
            Write-ColorOutput "Container $container is not running" -Type Error
            $allHealthy = $false
        }
    }
    
    # Test service connectivity
    Write-ColorOutput "Testing service connectivity..." -Type Debug
    
    # Test Portainer
    $portainerPort = [Environment]::GetEnvironmentVariable('PORTAINER_PORT', 'Process')
    $portainerUrl = "http://localhost:$portainerPort"
    
    try {
        $response = Invoke-WebRequest -Uri $portainerUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-ColorOutput "✓ Portainer is accessible at $portainerUrl (Status: $($response.StatusCode))" -Type Debug
    }
    catch {
        Write-ColorOutput "Portainer may not be fully ready at $portainerUrl" -Type Warn
        $allHealthy = $false
    }
    
    # Test SurrealDB
    $surrealdbPort = [Environment]::GetEnvironmentVariable('SURREALDB_PORT', 'Process')
    $surrealdbUrl = "http://localhost:$surrealdbPort/health"
    
    try {
        $response = Invoke-WebRequest -Uri $surrealdbUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-ColorOutput "✓ SurrealDB is accessible at http://localhost:$surrealdbPort (Status: $($response.StatusCode))" -Type Debug
    }
    catch {
        Write-ColorOutput "SurrealDB may not be fully ready at http://localhost:$surrealdbPort" -Type Warn
        $allHealthy = $false
    }
    
    # Test inter-service communication
    Write-ColorOutput "Testing inter-service communication..." -Type Debug
    try {
        docker-compose exec -T portainer ping -c 1 core-surrealdb 2>$null | Out-Null
        Write-ColorOutput "✓ Portainer can communicate with SurrealDB" -Type Debug
    }
    catch {
        Write-ColorOutput "Inter-service communication test failed" -Type Warn
        $allHealthy = $false
    }
    
    if ($allHealthy) {
        Write-ColorOutput "Deployment verification completed successfully" -Type Success
        # Remove rollback state on successful deployment
        if (Test-Path $Script:RollbackStateFile) {
            Remove-Item $Script:RollbackStateFile -Force
        }
    }
    else {
        Write-ColorOutput "Some verification checks failed. Services may need time to fully initialize." -Type Warn
        Write-ColorOutput "Run '.\status.ps1' to check service health, or '.\logs.ps1' to view logs." -Type Info
    }
}

# Deployment summary
function Show-DeploymentSummary {
    Write-ColorOutput "Step 8: Deployment Summary" -Type Step
    
    $portainerPort = [Environment]::GetEnvironmentVariable('PORTAINER_PORT', 'Process')
    $surrealdbPort = [Environment]::GetEnvironmentVariable('SURREALDB_PORT', 'Process')
    
    # Get local IP address
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Select-Object -First 1).IPAddress
    if (-not $localIP) {
        $localIP = "localhost"
    }
    
    $summary = @"

🎉 Core Services Deployment Complete!

📊 Service Access URLs:
• Portainer:  http://${localIP}:${portainerPort}
• SurrealDB:  http://${localIP}:${surrealdbPort}
• Doppler:    Internal service (no direct access)

🔧 Management Commands:
• Check Status:    .\status.ps1
• View Logs:       .\logs.ps1
• Create Backup:   .\backup.ps1
• Stop Services:   .\stop.ps1
• Update Services: .\update.ps1

📁 Important Paths:
• Data Directory:   C:\DockerData\core\
• Backup Directory: C:\DockerBackups\core\
• Logs:            $($Script:LogFile)

🔐 Security Notes:
• Portainer: Create admin account on first visit
• SurrealDB: Authentication via Doppler-managed credentials
• Network:   Services isolated on core-network (172.20.0.0/16)

📖 Next Steps:
1. Visit Portainer UI to set up admin account
2. Configure additional secrets in Doppler dashboard
3. Review and customize .env file for production use
4. Set up automated backups using Task Scheduler

For troubleshooting and advanced configuration, see README.md

"@
    
    Write-Host $summary -ForegroundColor Green
    Write-ColorOutput "Deployment completed successfully at $(Get-Date)" -Type Success
}

# Main execution function
function Invoke-Main {
    # Initialize log file
    "=== Core Services Deployment Started at $(Get-Date) ===" | Set-Content $Script:LogFile -Encoding UTF8
    
    Write-ColorOutput "Starting unified core services deployment..." -Type Info
    Write-ColorOutput "Script directory: $Script:ScriptDir" -Type Debug
    Write-ColorOutput "Options: Verbose=$Script:VerboseEnabled, DryRun=$DryRun, Force=$Force, SkipBackup=$SkipBackup, AutoConfirm=$AutoConfirm" -Type Debug
    
    if ($DryRun) {
        Write-ColorOutput "Running in DRY RUN mode - no changes will be made" -Type Warn
    }
    
    # Set error handler
    Set-ErrorHandler
    
    # Execute deployment steps
    Test-SystemRequirements
    Test-Configuration
    New-DirectoryStructure
    New-Backup
    Test-DopplerConnectivity
    Start-Deployment
    Test-Deployment
    Show-DeploymentSummary
    
    Write-ColorOutput "Deployment script completed successfully" -Type Success
}

# Script entry point
if ($Help) {
    Show-Help
    exit 0
}

# Change to script directory
Set-Location $Script:ScriptDir

# Execute main function
try {
    Invoke-Main
}
catch {
    Write-ColorOutput "Deployment failed: $($_.Exception.Message)" -Type Error
    exit 1
}
finally {
    Invoke-Cleanup
}