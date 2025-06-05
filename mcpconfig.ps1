<#
.SYNOPSIS
    MCP Environment Setup Script for Windows
.DESCRIPTION
    Sets up the MCP environment with Docker volumes, networks, and services.
    Compatible with Windows and WSL Docker environments.
.NOTES
    File Name  : mcpconfig.ps1
    Author     : MCP Team
    Updated    : June 2025
    Requires   : PowerShell 5.1 or later, Docker
#>

# Use strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script constants
$SCRIPT_VERSION = "1.2.0"
$MIN_DOCKER_VERSION = "20.10.0"
$REQUIRED_DIRS = @("data", "logs", "cache", "init-db", "secrets")
$REQUIRED_VOLUMES = @("mcp-data", "mcp-logs", "mcp-cache")
$MCP_NETWORK = "mcp-network"
$MCP_SUBNET = "172.40.1.0/24"
$HEALTH_CHECK_URL = "http://localhost:8811/health"
$HEALTH_CHECK_TIMEOUT = 30  # seconds

# Helper functions
function Format-ElapsedTime {
    param ([System.Diagnostics.Stopwatch]$Stopwatch)
    $elapsed = $Stopwatch.Elapsed
    return "{0:00}:{1:00}:{2:00}.{3:00}" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds, ($elapsed.Milliseconds / 10)
}

function Test-CommandExists {
    param ([string]$Command)
    return [bool](Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

function Compare-Versions {
    param (
        [Parameter(Mandatory=$true)][string]$Version1,
        [Parameter(Mandatory=$true)][string]$Version2
    )
    
    $v1 = [System.Version]::new(($Version1 -replace "[^\d\.].*$"))
    $v2 = [System.Version]::new(($Version2 -replace "[^\d\.].*$"))
    
    return $v1.CompareTo($v2)
}

function Write-LogMessage {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Type = "INFO",
        [Parameter(Mandatory=$false)][switch]$NoNewline
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        "INFO" = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR" = "Red"
        "DEBUG" = "Gray"
    }
    
    $color = $colorMap[$Type]
    if (-not $color) { $color = "White" }
    
    $formattedMessage = "[$timestamp] $Type`: $Message"
    Write-Host $formattedMessage -ForegroundColor $color -NoNewline:$NoNewline
}

function New-SecureDirectory {
    param ([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-LogMessage "Creating directory: $Path" -Type "INFO"
        $null = New-Item -ItemType Directory -Path $Path -Force
        
        # Apply more restrictive permissions on Windows
        try {
            $acl = Get-Acl -Path $Path
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($rule)
            Set-Acl -Path $Path -AclObject $acl
            Write-LogMessage "Secured directory permissions: $Path" -Type "SUCCESS"
        } catch {
            Write-LogMessage "Warning: Could not set secure permissions on $Path. Using defaults." -Type "WARNING"
        }
    } else {
        Write-LogMessage "Directory exists: $Path" -Type "SUCCESS"
    }
}

# Begin script execution
$timer = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "`n┌─────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│ MCP Environment Setup v$SCRIPT_VERSION        │" -ForegroundColor Cyan
Write-Host "│ " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss").PadRight(39) + "│" -ForegroundColor Cyan
Write-Host "└─────────────────────────────────────────┘`n" -ForegroundColor Cyan

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
Write-LogMessage "PowerShell Version: $($psVersion.Major).$($psVersion.Minor).$($psVersion.Build)" -Type "INFO"

# Check Docker availability
if (-not (Test-CommandExists "docker")) {
    Write-LogMessage "Docker is not installed or not in PATH!" -Type "ERROR"
    Write-LogMessage "Please install Docker Desktop and try again." -Type "ERROR"
    exit 1
}

try {
    $dockerVersionOutput = docker version --format "{{.Server.Version}}" 2>$null
    if (-not $dockerVersionOutput) {
        $dockerVersionOutput = (docker version | Select-String -Pattern "Server: Docker Engine") -replace "Server: Docker Engine",""
    }
    $dockerVersion = $dockerVersionOutput.Trim()
    
    Write-LogMessage "Docker is available (v$dockerVersion)" -Type "SUCCESS"
    
    # Check minimum Docker version
    if ((Compare-Versions -Version1 $dockerVersion -Version2 $MIN_DOCKER_VERSION) -lt 0) {
        Write-LogMessage "Docker version $dockerVersion is below minimum required version $MIN_DOCKER_VERSION" -Type "WARNING"
        Write-LogMessage "Some features may not work correctly. Consider upgrading Docker." -Type "WARNING"
    }
} catch {
    Write-LogMessage "Docker is not running or not accessible!" -Type "ERROR"
    Write-LogMessage "Please start Docker Desktop and try again." -Type "ERROR"
    exit 1
}

# Load .env file into environment
$envFile = ".\.env"
if (Test-Path $envFile) {
    Write-LogMessage "Loading environment variables from .env" -Type "INFO"
    $envCount = 0
    
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^\s*#") { return }
        if ($_ -match "^\s*$") { return }
        $parts = $_ -split '=', 2
        if ($parts.Length -eq 2) {
            [System.Environment]::SetEnvironmentVariable($parts[0], $parts[1])
            $envCount++
        }
    }
    Write-LogMessage "Loaded $envCount environment variables" -Type "SUCCESS"
} else {
    Write-LogMessage ".env file not found. Using default values." -Type "WARNING"
}

# Ensure directories exist with proper permissions
Write-LogMessage "Setting up directories..." -Type "INFO"
foreach ($dir in $REQUIRED_DIRS) {
    New-SecureDirectory -Path $dir
}

# Create Docker volumes if missing
Write-LogMessage "Setting up Docker volumes..." -Type "INFO"
foreach ($volume in $REQUIRED_VOLUMES) {
    try {
        $null = docker volume inspect $volume 2>$null
        Write-LogMessage "Volume exists: $volume" -Type "SUCCESS"
    } catch {
        try {
            $null = docker volume create $volume
            Write-LogMessage "Created volume: $volume" -Type "SUCCESS"
        } catch {
            Write-LogMessage "Failed to create volume: $volume - $($_.Exception.Message)" -Type "ERROR"
            exit 1
        }
    }
}

# Create network if not exists
Write-LogMessage "Setting up Docker network..." -Type "INFO"
try {
    $null = docker network inspect $MCP_NETWORK 2>$null
    Write-LogMessage "Network exists: $MCP_NETWORK" -Type "SUCCESS"
} catch {
    try {
        $null = docker network create --subnet=$MCP_SUBNET $MCP_NETWORK
        Write-LogMessage "Created network: $MCP_NETWORK ($MCP_SUBNET)" -Type "SUCCESS"
    } catch {
        Write-LogMessage "Failed to create network: $MCP_NETWORK - $($_.Exception.Message)" -Type "ERROR"
        exit 1
    }
}

# Check for docker-compose availability
if (-not (Test-CommandExists "docker-compose") -and -not (Test-CommandExists "docker" "compose")) {
    Write-LogMessage "docker-compose is not available. Attempting to use 'docker compose' instead." -Type "WARNING"
    $composeCommand = "docker compose"
} else {
    $composeCommand = "docker-compose"
}

# Pull images before starting
Write-LogMessage "Pulling Docker images (this may take a few minutes)..." -Type "INFO"
try {
    if ($composeCommand -eq "docker-compose") {
        Invoke-Expression "docker-compose pull" | Out-Null
    } else {
        Invoke-Expression "docker compose pull" | Out-Null
    }
    Write-LogMessage "Images pulled successfully" -Type "SUCCESS"
} catch {
    Write-LogMessage "Warning: Some images could not be pulled. Continuing with local images if available." -Type "WARNING"
}

# Start Docker Compose
Write-LogMessage "Starting services with Docker Compose..." -Type "INFO"
try {
    if ($composeCommand -eq "docker-compose") {
        Invoke-Expression "docker-compose up -d" | Out-Null
    } else {
        Invoke-Expression "docker compose up -d" | Out-Null
    }
    Write-LogMessage "Services started successfully" -Type "SUCCESS"
} catch {
    Write-LogMessage "Failed to start services: $($_.Exception.Message)" -Type "ERROR"
    exit 1
}

# Wait and run health check
Write-LogMessage "Waiting for services to initialize ($HEALTH_CHECK_TIMEOUT seconds timeout)..." -Type "INFO"

$healthCheckTimer = [System.Diagnostics.Stopwatch]::StartNew()
$healthy = $false

while ($healthCheckTimer.Elapsed.TotalSeconds -lt $HEALTH_CHECK_TIMEOUT) {
    try {
        $response = Invoke-WebRequest -Uri $HEALTH_CHECK_URL -UseBasicParsing -ErrorAction SilentlyContinue -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            $healthy = $true
            break
        }
    } catch {
        # Continue waiting
    }
    
    # Progress indicator
    Write-Host "." -NoNewline -ForegroundColor Yellow
    Start-Sleep -Seconds 2
}

Write-Host ""  # New line after progress dots

if ($healthy) {
    Write-LogMessage "MCP Server is healthy! (Time: $([math]::Round($healthCheckTimer.Elapsed.TotalSeconds, 1))s)" -Type "SUCCESS"
} else {
    Write-LogMessage "MCP Server did not respond within timeout period ($HEALTH_CHECK_TIMEOUT seconds)" -Type "WARNING"
    Write-LogMessage "Run 'health-check.bat' to troubleshoot or check container logs with 'docker logs mcp-server'" -Type "INFO"
}

# Display service info
Write-LogMessage "Checking service status..." -Type "INFO"
try {
    $containers = docker ps --filter "name=mcp" --format "{{.Names}}: {{.Status}}"
    
    Write-Host "`nService Status:" -ForegroundColor Cyan
    $containers -split "`n" | ForEach-Object {
        if ($_ -match "Up ") {
            Write-Host "  ✅ $_" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $_" -ForegroundColor Red
        }
    }
} catch {
    Write-LogMessage "Could not retrieve container status" -Type "WARNING"
}

# Script completion
$timer.Stop()
Write-Host "`n┌─────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│ Setup completed in $(Format-ElapsedTime -Stopwatch $timer)            │" -ForegroundColor Green
Write-Host "└─────────────────────────────────────────┘" -ForegroundColor Green

Write-Host "`nMCP Access Points:" -ForegroundColor Cyan
Write-Host "  • MCP Server: http://localhost:8811" -ForegroundColor White
Write-Host "  • Traefik Dashboard: http://localhost:8080" -ForegroundColor White

if (-not $healthy) {
    Write-Host "`nNOTE: MCP may still be initializing. Run 'health-check.bat' to verify status." -ForegroundColor Yellow
}

Write-Host "`nFor troubleshooting, use: 'docker logs mcp-server'" -ForegroundColor Cyan
