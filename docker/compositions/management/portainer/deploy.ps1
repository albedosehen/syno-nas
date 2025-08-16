# Portainer Deployment Script for Synology NAS (Windows PowerShell)
# This script automates the deployment of Portainer with proper configuration

param(
    [Parameter(Position=0)]
    [ValidateSet("deploy", "status", "logs", "help")]
    [string]$Action = "deploy"
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectName = "portainer"
$ComposeFile = "docker-compose.yml"
$EnvFile = ".env"
$EnvExampleFile = ".env.example"

# Set location to script directory
Set-Location $ScriptDir

# Functions for colored output
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check if Docker is available
    try {
        $null = docker --version
        Write-Success "Docker is available"
    }
    catch {
        Write-ErrorMsg "Docker is not installed or not in PATH"
        exit 1
    }
    
    # Check if Docker is running
    try {
        $null = docker info 2>$null
        Write-Success "Docker daemon is running"
    }
    catch {
        Write-ErrorMsg "Docker daemon is not running"
        Write-Info "Please start Docker Desktop or Docker service"
        exit 1
    }
    
    # Check if Docker Compose is available
    try {
        $null = docker-compose --version
        Write-Success "Docker Compose is available"
    }
    catch {
        Write-ErrorMsg "Docker Compose is not installed or not in PATH"
        exit 1
    }
    
    Write-Success "Prerequisites check passed"
}

# Setup environment file
function Initialize-Environment {
    Write-Info "Setting up environment configuration..."
    
    if (-not (Test-Path $EnvFile)) {
        if (Test-Path $EnvExampleFile) {
            Copy-Item $EnvExampleFile $EnvFile
            Write-Success "Created .env file from .env.example"
            Write-Warning "Please review and customize the .env file before proceeding"
            
            # Prompt user to edit the file
            $response = Read-Host "Do you want to edit the .env file now? (y/n)"
            if ($response -eq "y" -or $response -eq "Y") {
                if (Get-Command notepad -ErrorAction SilentlyContinue) {
                    notepad $EnvFile
                } elseif (Get-Command code -ErrorAction SilentlyContinue) {
                    code $EnvFile
                } else {
                    Write-Info "Please edit $EnvFile manually"
                }
            }
        }
        else {
            Write-ErrorMsg ".env.example file not found"
            exit 1
        }
    }
    else {
        Write-Info ".env file already exists"
    }
}

# Create necessary directories
function New-Directories {
    Write-Info "Creating necessary directories..."
    
    # Create data directory if it doesn't exist
    if (-not (Test-Path "data")) {
        New-Item -ItemType Directory -Path "data" | Out-Null
        Write-Success "Created data directory"
    }
    
    Write-Success "Directory setup completed"
}

# Check for port conflicts
function Test-Ports {
    Write-Info "Checking for port conflicts..."
    
    # Load environment variables
    if (Test-Path $EnvFile) {
        Get-Content $EnvFile | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
            }
        }
    }
    
    $portainerPort = if ($env:PORTAINER_PORT) { $env:PORTAINER_PORT } else { "9000" }
    $edgePort = if ($env:PORTAINER_EDGE_PORT) { $env:PORTAINER_EDGE_PORT } else { "8000" }
    
    # Check if ports are in use
    $portsInUse = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object LocalPort
    
    if ($portsInUse.LocalPort -contains $portainerPort) {
        Write-ErrorMsg "Port $portainerPort is already in use"
        Write-Info "Please change PORTAINER_PORT in .env file or stop the service using this port"
        exit 1
    }
    
    if ($portsInUse.LocalPort -contains $edgePort) {
        Write-ErrorMsg "Port $edgePort is already in use"
        Write-Info "Please change PORTAINER_EDGE_PORT in .env file or stop the service using this port"
        exit 1
    }
    
    Write-Success "Port check passed"
}

# Deploy Portainer
function Start-PortainerDeployment {
    Write-Info "Deploying Portainer..."
    
    # Pull latest images
    Write-Info "Pulling latest Portainer image..."
    docker-compose pull
    
    # Start the services
    Write-Info "Starting Portainer services..."
    docker-compose up -d
    
    Write-Success "Portainer deployed successfully"
}

# Wait for service to be ready
function Wait-ForService {
    Write-Info "Waiting for Portainer to be ready..."
    
    # Load environment variables
    if (Test-Path $EnvFile) {
        Get-Content $EnvFile | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
            }
        }
    }
    
    $port = if ($env:PORTAINER_PORT) { $env:PORTAINER_PORT } else { "9000" }
    $maxAttempts = 30
    $attempt = 1
    
    while ($attempt -le $maxAttempts) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port" -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-Success "Portainer is ready and responding"
                return $true
            }
        }
        catch {
            # Service not ready yet
        }
        
        Write-Info "Waiting for Portainer to start (attempt $attempt/$maxAttempts)..."
        Start-Sleep -Seconds 2
        $attempt++
    }
    
    Write-ErrorMsg "Portainer did not become ready within expected time"
    Write-Info "Check the logs with: docker-compose logs portainer"
    return $false
}

# Display deployment summary
function Show-Summary {
    Write-Info "Deployment Summary"
    Write-Host "===================="
    
    # Load environment variables
    if (Test-Path $EnvFile) {
        Get-Content $EnvFile | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
            }
        }
    }
    
    $port = if ($env:PORTAINER_PORT) { $env:PORTAINER_PORT } else { "9000" }
    $edgePort = if ($env:PORTAINER_EDGE_PORT) { $env:PORTAINER_EDGE_PORT } else { "8000" }
    
    # Get local IP address
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Select-Object -First 1).IPAddress
    if (-not $localIP) {
        $localIP = "localhost"
    }
    
    Write-Host "Service: Portainer Community Edition"
    
    # Check if container is running
    $runningContainers = docker-compose ps --services --filter status=running
    $status = if ($runningContainers -contains "portainer") { "Running" } else { "Not Running" }
    Write-Host "Status: $status"
    
    Write-Host "Web Interface: http://${localIP}:$port"
    Write-Host "Edge Port: $edgePort"
    Write-Host "Data Directory: $(Get-Location)\data"
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "1. Open your web browser and navigate to the Web Interface URL above"
    Write-Host "2. Create your initial administrator account"
    Write-Host "3. Select 'Local' environment to manage this Docker instance"
    Write-Host ""
    Write-Host "Management Commands:"
    Write-Host "- View logs: docker-compose logs portainer"
    Write-Host "- Stop service: docker-compose stop"
    Write-Host "- Start service: docker-compose start"
    Write-Host "- Restart service: docker-compose restart"
    Write-Host "- Update service: .\update.ps1 (if available)"
    Write-Host ""
}

# Show help
function Show-Help {
    Write-Host "Portainer Deployment Script"
    Write-Host ""
    Write-Host "Usage: .\deploy.ps1 [action]"
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  deploy    Deploy Portainer service (default)"
    Write-Host "  status    Show current status"
    Write-Host "  logs      Show service logs"
    Write-Host "  help      Show this help message"
    Write-Host ""
}

# Show status
function Show-Status {
    Write-Host "Portainer Status:"
    docker-compose ps
}

# Show logs
function Show-Logs {
    docker-compose logs portainer
}

# Main execution
switch ($Action) {
    "help" {
        Show-Help
        exit 0
    }
    "status" {
        Show-Status
        exit 0
    }
    "logs" {
        Show-Logs
        exit 0
    }
    "deploy" {
        Write-Host "========================================"
        Write-Host "    Portainer Deployment Script"
        Write-Host "========================================"
        Write-Host ""
        
        Test-Prerequisites
        Initialize-Environment
        New-Directories
        Test-Ports
        Start-PortainerDeployment
        
        if (Wait-ForService) {
            Show-Summary
            Write-Success "Portainer deployment completed successfully!"
        }
        else {
            Write-ErrorMsg "Deployment completed but service may not be fully ready"
            Write-Info "Check logs with: docker-compose logs portainer"
        }
    }
    default {
        Write-ErrorMsg "Unknown action: $Action"
        Write-Host "Use '.\deploy.ps1 help' for usage information"
        exit 1
    }
}