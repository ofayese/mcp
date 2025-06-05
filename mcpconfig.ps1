# MCP Environment Setup - PowerShell
# Compatible with Windows and WSL Docker environments

Write-Host "`n🔧 Starting MCP setup..." -ForegroundColor Cyan

# Check Docker availability
try {
    $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
    Write-Host "✅ Docker is available (v$dockerVersion)"
} catch {
    Write-Host "❌ Docker is not running or not accessible!" -ForegroundColor Red
    Write-Host "   Please start Docker Desktop and try again." -ForegroundColor Yellow
    exit 1
}

# Load .env file into environment
$envFile = ".\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^\s*#") { return }
        if ($_ -match "^\s*$") { return }
        $parts = $_ -split '=', 2
        if ($parts.Length -eq 2) {
            [System.Environment]::SetEnvironmentVariable($parts[0], $parts[1])
            Write-Host "🔑 Loaded: $($parts[0])"
        }
    }
} else {
    Write-Host "⚠️  .env file not found." -ForegroundColor Yellow
}

# Ensure directories exist
$dirs = @("data", "logs", "cache", "init-db")
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d | Out-Null
        Write-Host "📁 Created directory: $d"
    } else {
        Write-Host "✅ Directory exists: $d"
    }
}

# Create Docker volumes if missing
$volumes = @("mcp-data", "mcp-logs", "mcp-cache", "mcp-postgres-data")
foreach ($v in $volumes) {
    if (-not (docker volume inspect $v 2>$null)) {
        docker volume create $v | Out-Null
        Write-Host "📦 Created volume: $v"
    } else {
        Write-Host "✅ Volume exists: $v"
    }
}

# Create network if not exists
$network = "mcp-network"
if (-not (docker network inspect $network 2>$null)) {
    docker network create --subnet=172.40.1.0/24 $network | Out-Null
    Write-Host "🌐 Created network: $network"
} else {
    Write-Host "✅ Network exists: $network"
}

# Start Docker Compose
Write-Host "`n🚀 Starting services with Docker Compose..."
docker-compose up -d

# Wait and run health check
Start-Sleep -Seconds 10
$response = Invoke-WebRequest -Uri "http://localhost:8811/health" -UseBasicParsing -ErrorAction SilentlyContinue
if ($response.StatusCode -eq 200) {
    Write-Host "✅ MCP Server is healthy!" -ForegroundColor Green
} else {
    Write-Host "❌ MCP Server is not responding!" -ForegroundColor Red
}
