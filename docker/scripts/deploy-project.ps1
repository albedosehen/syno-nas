# Synology NAS Docker Management - Project Deployment Script (PowerShell)
# This script automates the deployment of the entire Docker management project
# with proper configuration, prerequisites checking, and service orchestration

param(
    [Parameter(Position=0)]
    [ValidateSet("deploy", "help")]
    [string]$Action = "deploy",
    
    [string]$Category = "",
    [string]$Service = "",
    [switch]$Parallel,
    [switch]$Force,
    [switch]$SkipPortainer,
    [switch]$SkipNetwork,
    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$Help
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$ProjectName = "syno-nas-docker-management"
$CompositionsDir = Join-Path $ProjectRoot "compositions"
$EnvFile = Join-Path $ProjectRoot ".env"
$EnvExampleFile = Join-Path $ProjectRoot ".env.example"

# Global variables for configuration
$Global:Config = @{}

# Set location to project root
Set-Location $ProjectRoot

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

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Magenta
}

function Write-Service {
    param([string]$Message)
    Write-Host "[SERVICE] $Message" -ForegroundColor Cyan
}

function Write-Verbose {
    param([string]$Message)
    if ($Verbose -or $Global:Config.VERBOSE_OUTPUT -eq "true") {
        Write-Info "VERBOSE: $Message"
    }
}

# Help function
function Show-Help {
    Write-Host "Synology NAS Docker Management - Project Deployment Script"
    Write-Host ""
    Write-Host "Usage: .\deploy-project.ps1 [options]"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -Category CATEGORY       Deploy only services in specified category"
    Write-Host "                          (management, media, productivity, networking)"
    Write-Host "  -Service SERVICE        Deploy only specified service"
    Write-Host "  -Parallel              Enable parallel service deployment"
    Write-Host "  -Force                 Force deployment even if services exist"
    Write-Host "  -SkipPortainer         Skip Portainer deployment"
    Write-Host "  -SkipNetwork           Skip network creation"
    Write-Host "  -DryRun                Show what would be deployed without executing"
    Write-Host "  -Verbose               Enable verbose output"
    Write-Host "  -Help                  Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\deploy-project.ps1                    Deploy all services"
    Write-Host "  .\deploy-project.ps1 -Category management    Deploy only management services"
    Write-Host "  .\deploy-project.ps1 -Service portainer      Deploy only Portainer"
    Write-Host "  .\deploy-project.ps1 -Parallel              Deploy all services in parallel"
    Write-Host "  .\deploy-project.ps1 -DryRun                Show deployment plan without executing"
    Write-Host ""
}

# Load global environment variables
function Load-GlobalConfig {
    if (Test-Path $EnvFile) {
        Write-Info "Loading global configuration from $EnvFile"
        Get-Content $EnvFile | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                $Global:Config[$Matches[1]] = $Matches[2]
                [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
            }
        }
    } else {
        Write-Warning "Global .env file not found, using defaults"
    }
    
    # Set defaults for critical variables
    if (-not $Global:Config.PUID) { $Global:Config.PUID = "1000" }
    if (-not $Global:Config.PGID) { $Global:Config.PGID = "1000" }
    if (-not $Global:Config.TZ) { $Global:Config.TZ = "UTC" }
    if (-not $Global:Config.DOCKER_NETWORK_NAME) { $Global:Config.DOCKER_NETWORK_NAME = "syno-nas-network" }
    if (-not $Global:Config.PARALLEL_OPERATIONS) { $Global:Config.PARALLEL_OPERATIONS = "true" }
    if (-not $Global:Config.MAX_PARALLEL_JOBS) { $Global:Config.MAX_PARALLEL_JOBS = "4" }
    if (-not $Global:Config.VERBOSE_OUTPUT) { $Global:Config.VERBOSE_OUTPUT = "false" }
    if (-not $Global:Config.DRY_RUN_MODE) { $Global:Config.DRY_RUN_MODE = "false" }
}

# Check prerequisites
function Test-Prerequisites {
    Write-Step "Checking prerequisites..."
    
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
    
    # Check available disk space (basic check)
    $drive = (Get-Location).Drive
    $freeSpace = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($drive.Name)'").FreeSpace
    if ($freeSpace -lt 1GB) {
        Write-Warning "Low disk space detected. Ensure sufficient space for Docker images and data"
    }
    
    Write-Success "Prerequisites check passed"
}

# Setup global environment
function Initialize-GlobalEnvironment {
    Write-Step "Setting up global environment..."
    
    if (-not (Test-Path $EnvFile)) {
        if (Test-Path $EnvExampleFile) {
            if ($DryRun) {
                Write-Info "DRY RUN: Would copy $EnvExampleFile to $EnvFile"
            } else {
                Copy-Item $EnvExampleFile $EnvFile
                Write-Success "Created global .env file from .env.example"
                Write-Warning "Please review and customize the global .env file"
                
                # Prompt user to edit the file in interactive mode
                if (-not $DryRun) {
                    $response = Read-Host "Do you want to edit the global .env file now? (y/n)"
                    if ($response -eq "y" -or $response -eq "Y") {
                        if (Get-Command notepad -ErrorAction SilentlyContinue) {
                            notepad $EnvFile
                        } elseif (Get-Command code -ErrorAction SilentlyContinue) {
                            code $EnvFile
                        } else {
                            Write-Info "Please edit $EnvFile manually"
                        }
                        Write-Info "Please run the script again after configuring the environment"
                        exit 0
                    }
                }
            }
        } else {
            Write-ErrorMsg "Global .env.example file not found"
            exit 1
        }
    } else {
        Write-Info "Global .env file already exists"
    }
    
    # Reload configuration after potential changes
    Load-GlobalConfig
}

# Create global directories
function New-GlobalDirectories {
    Write-Step "Creating global directories..."
    
    $directories = @(
        ($Global:Config.DATA_BASE_PATH -or "/volume1/docker/data"),
        ($Global:Config.BACKUP_BASE_PATH -or "/volume1/docker/backups"),
        (Join-Path $ProjectRoot "logs")
    )
    
    foreach ($dir in $directories) {
        if ($DryRun) {
            Write-Info "DRY RUN: Would create directory: $dir"
        } else {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Verbose "Created directory: $dir"
            }
        }
    }
    
    Write-Success "Global directories created and configured"
}

# Create Docker network
function New-DockerNetwork {
    if ($SkipNetwork) {
        Write-Info "Skipping Docker network creation"
        return
    }
    
    $networkName = $Global:Config.DOCKER_NETWORK_NAME
    Write-Step "Creating Docker network: $networkName"
    
    $existingNetwork = docker network ls --format "{{.Name}}" | Where-Object { $_ -eq $networkName }
    
    if ($existingNetwork) {
        Write-Info "Docker network '$networkName' already exists"
    } else {
        if ($DryRun) {
            Write-Info "DRY RUN: Would create Docker network: $networkName"
        } else {
            docker network create $networkName --driver bridge
            Write-Success "Created Docker network: $networkName"
        }
    }
}

# Discover available services
function Get-Services {
    param([string]$Category = "all")
    
    Write-Verbose "Discovering services in category: $Category"
    
    $services = @()
    
    if ($Category -eq "all") {
        # Find all docker-compose.yml files in compositions directory
        $composeFiles = Get-ChildItem -Path $CompositionsDir -Name "docker-compose.yml" -Recurse
        foreach ($file in $composeFiles) {
            $serviceDir = Split-Path -Parent (Join-Path $CompositionsDir $file)
            $services += $serviceDir
        }
    } else {
        # Find services in specific category
        $categoryDir = Join-Path $CompositionsDir $Category
        if (Test-Path $categoryDir) {
            $composeFiles = Get-ChildItem -Path $categoryDir -Name "docker-compose.yml" -Recurse
            foreach ($file in $composeFiles) {
                $serviceDir = Split-Path -Parent (Join-Path $categoryDir $file)
                $services += $serviceDir
            }
        }
    }
    
    return $services
}

# Deploy single service
function Deploy-Service {
    param([string]$ServiceDir)
    
    $serviceName = Split-Path -Leaf $ServiceDir
    $category = Split-Path -Leaf (Split-Path -Parent $ServiceDir)
    
    Write-Service "Deploying $category/$serviceName"
    
    $composeFile = Join-Path $ServiceDir "docker-compose.yml"
    if (-not (Test-Path $composeFile)) {
        Write-ErrorMsg "No docker-compose.yml found in $ServiceDir"
        return $false
    }
    
    Set-Location $ServiceDir
    
    # Check if service deployment script exists
    $deployScript = Join-Path $ServiceDir "deploy.ps1"
    if (Test-Path $deployScript) {
        Write-Verbose "Using service-specific deployment script"
        if ($DryRun) {
            Write-Info "DRY RUN: Would execute .\deploy.ps1"
        } else {
            & $deployScript
        }
    } else {
        # Generic deployment process
        Write-Verbose "Using generic deployment process"
        
        # Setup service environment
        $envFile = Join-Path $ServiceDir ".env"
        $envExampleFile = Join-Path $ServiceDir ".env.example"
        
        if (-not (Test-Path $envFile) -and (Test-Path $envExampleFile)) {
            if ($DryRun) {
                Write-Info "DRY RUN: Would copy .env.example to .env"
            } else {
                Copy-Item $envExampleFile $envFile
                Write-Info "Created .env from .env.example for $serviceName"
            }
        }
        
        if ($DryRun) {
            Write-Info "DRY RUN: Would execute docker-compose up -d"
        } else {
            # Pull images and deploy
            docker-compose pull
            docker-compose up -d
        }
    }
    
    Write-Success "Deployed $category/$serviceName"
    return $true
}

# Deploy services in parallel
function Deploy-ServicesParallel {
    param([string[]]$Services)
    
    $maxJobs = [int]($Global:Config.MAX_PARALLEL_JOBS -or 4)
    Write-Info "Deploying $($Services.Count) services in parallel (max $maxJobs jobs)"
    
    $jobs = @()
    
    foreach ($service in $Services) {
        # Limit concurrent jobs
        while ($jobs.Count -ge $maxJobs) {
            $jobs = $jobs | Where-Object { $_.State -eq "Running" }
            Start-Sleep -Seconds 1
        }
        
        # Start service deployment in background
        $job = Start-Job -ScriptBlock {
            param($ServiceDir, $DryRun)
            
            # Re-import functions needed in job context
            function Deploy-Service {
                param([string]$ServiceDir)
                # Simplified version for job context
                Set-Location $ServiceDir
                if (-not $DryRun) {
                    docker-compose pull
                    docker-compose up -d
                }
                return $true
            }
            
            Deploy-Service $ServiceDir
        } -ArgumentList $service, $DryRun
        
        $jobs += $job
    }
    
    # Wait for all jobs to complete
    $jobs | Wait-Job | Out-Null
    $jobs | Remove-Job
}

# Deploy services sequentially
function Deploy-ServicesSequential {
    param([string[]]$Services)
    
    Write-Info "Deploying $($Services.Count) services sequentially"
    
    foreach ($service in $Services) {
        $success = Deploy-Service $service
        if (-not $success) {
            Write-ErrorMsg "Failed to deploy service in $service"
        }
    }
}

# Wait for service health
function Wait-ForServiceHealth {
    param([string]$ServiceDir, [int]$Timeout = 120)
    
    $serviceName = Split-Path -Leaf $ServiceDir
    Write-Info "Waiting for $serviceName to be healthy..."
    
    Set-Location $ServiceDir
    
    $elapsed = 0
    while ($elapsed -lt $Timeout) {
        # Check if containers are running
        $runningContainers = docker-compose ps --services --filter status=running
        if ($runningContainers) {
            Write-Verbose "$serviceName appears to be running"
            return $true
        }
        
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    
    Write-Warning "$serviceName did not become healthy within $Timeout seconds"
    return $false
}

# Verify deployment
function Test-Deployment {
    Write-Step "Verifying deployment..."
    
    $services = @()
    if ($Service) {
        $services = Get-ChildItem -Path $CompositionsDir -Directory -Recurse | Where-Object { $_.Name -eq $Service }
    } elseif ($Category) {
        $services = Get-Services $Category
    } else {
        $services = Get-Services "all"
    }
    
    $failedServices = @()
    
    foreach ($serviceDir in $services) {
        if (Test-Path $serviceDir) {
            $serviceName = Split-Path -Leaf $serviceDir
            
            Set-Location $serviceDir
            
            if ($DryRun) {
                Write-Info "DRY RUN: Would verify $serviceName"
                continue
            }
            
            # Check if containers are running
            $runningContainers = docker-compose ps --services --filter status=running
            if ($runningContainers) {
                Write-Success "$serviceName is running"
                Write-Verbose "Waiting for $serviceName health check..."
                Wait-ForServiceHealth $serviceDir 30 | Out-Null
            } else {
                Write-ErrorMsg "$serviceName is not running"
                $failedServices += $serviceName
            }
        }
    }
    
    if ($failedServices.Count -eq 0) {
        Write-Success "All services are running successfully"
        return $true
    } else {
        Write-ErrorMsg "Failed services: $($failedServices -join ', ')"
        return $false
    }
}

# Display deployment summary
function Show-DeploymentSummary {
    Write-Step "Deployment Summary"
    Write-Host "========================================"
    
    # Project information
    Write-Host "Project: $ProjectName"
    Write-Host "Location: $ProjectRoot"
    Write-Host "Network: $($Global:Config.DOCKER_NETWORK_NAME)"
    Write-Host ""
    
    # Deployed services
    Write-Host "Deployed Services:"
    
    $services = @()
    if ($Service) {
        $services = Get-ChildItem -Path $CompositionsDir -Directory -Recurse | Where-Object { $_.Name -eq $Service }
    } elseif ($Category) {
        $services = Get-Services $Category
    } else {
        $services = Get-Services "all"
    }
    
    foreach ($serviceDir in $services) {
        if (Test-Path $serviceDir) {
            $serviceName = Split-Path -Leaf $serviceDir
            $categoryName = Split-Path -Leaf (Split-Path -Parent $serviceDir)
            
            Set-Location $serviceDir
            
            if ($DryRun) {
                Write-Host "  - $categoryName/$serviceName (DRY RUN)"
            } else {
                $status = "Stopped"
                $runningContainers = docker-compose ps --services --filter status=running
                if ($runningContainers) {
                    $status = "Running"
                }
                Write-Host "  - $categoryName/$serviceName`: $status"
            }
        }
    }
    
    Write-Host ""
    Write-Host "Management URLs:"
    if (-not $SkipPortainer -and (-not $Service -or $Service -eq "portainer")) {
        $portainerEnv = Join-Path $CompositionsDir "management\portainer\.env"
        $portainerPort = "9000"
        if (Test-Path $portainerEnv) {
            $portLine = Get-Content $portainerEnv | Where-Object { $_ -match "^PORTAINER_PORT=" }
            if ($portLine) {
                $portainerPort = ($portLine -split "=")[1]
            }
        }
        
        # Get local IP address
        $localIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Select-Object -First 1).IPAddress
        if (-not $localIP) {
            $localIP = "localhost"
        }
        
        Write-Host "  - Portainer: http://${localIP}:$portainerPort"
    }
    
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "1. Access the Portainer web interface to manage containers"
    Write-Host "2. Review service logs: docker-compose logs -f <service>"
    Write-Host "3. Monitor system resources and container health"
    Write-Host "4. Set up automated backups and monitoring"
    Write-Host ""
}

# Main deployment process
function Start-Deployment {
    Write-Host "========================================"
    Write-Host "  Synology NAS Docker Management"
    Write-Host "     Project Deployment Script"
    Write-Host "========================================"
    Write-Host ""
    
    # Change to project root
    Set-Location $ProjectRoot
    
    # Load configuration first
    Load-GlobalConfig
    
    # Apply CLI overrides
    if ($DryRun) {
        $Global:Config.DRY_RUN_MODE = "true"
    }
    if ($Verbose) {
        $Global:Config.VERBOSE_OUTPUT = "true"
    }
    
    if ($Global:Config.DRY_RUN_MODE -eq "true") {
        Write-Warning "DRY RUN MODE - No changes will be made"
    }
    
    # Execute deployment steps
    Test-Prerequisites
    Initialize-GlobalEnvironment
    New-GlobalDirectories
    New-DockerNetwork
    
    # Determine services to deploy
    $servicesToDeploy = @()
    
    if ($Service) {
        # Deploy specific service
        $servicePaths = Get-ChildItem -Path $CompositionsDir -Directory -Recurse | Where-Object { $_.Name -eq $Service }
        
        if ($servicePaths) {
            $servicesToDeploy = @($servicePaths[0].FullName)
        }
        
        if ($servicesToDeploy.Count -eq 0) {
            Write-ErrorMsg "Service '$Service' not found"
            exit 1
        }
    } elseif ($Category) {
        # Deploy category services
        $servicesToDeploy = Get-Services $Category
        
        if ($servicesToDeploy.Count -eq 0) {
            Write-ErrorMsg "No services found in category '$Category'"
            exit 1
        }
    } else {
        # Deploy all services, prioritize management services
        $mgmtServices = Get-Services "management"
        $otherServices = Get-Services "all"
        
        # Filter out management services from other services
        $filteredServices = @()
        foreach ($service in $otherServices) {
            if ($service -notin $mgmtServices) {
                $filteredServices += $service
            }
        }
        
        # Deploy management services first, then others
        $servicesToDeploy = $mgmtServices + $filteredServices
    }
    
    Write-Info "Found $($servicesToDeploy.Count) services to deploy"
    
    # Deploy services
    if ($servicesToDeploy.Count -gt 0) {
        if ($Parallel -and $Global:Config.PARALLEL_OPERATIONS -eq "true" -and $servicesToDeploy.Count -gt 1) {
            Deploy-ServicesParallel $servicesToDeploy
        } else {
            Deploy-ServicesSequential $servicesToDeploy
        }
        
        # Verify deployment
        if ($Global:Config.DRY_RUN_MODE -ne "true") {
            Start-Sleep -Seconds 5  # Give services time to start
            Test-Deployment | Out-Null
        }
    } else {
        Write-Warning "No services found to deploy"
    }
    
    # Show summary
    Show-DeploymentSummary
    
    if ($Global:Config.DRY_RUN_MODE -ne "true") {
        Write-Success "Project deployment completed successfully!"
    } else {
        Write-Info "DRY RUN completed - no changes were made"
    }
}

# Main execution
try {
    if ($Help -or $Action -eq "help") {
        Show-Help
        exit 0
    }
    
    Start-Deployment
}
catch {
    Write-ErrorMsg "Script failed: $($_.Exception.Message)"
    exit 1
}