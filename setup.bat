@echo off
:: Secure MCP Setup Bootstrap - Windows

echo 🔐 Secure MCP Setup Initializing...

:: Check Docker availability
docker info >nul 2>&1
if errorlevel 1 (
    echo ❌ Docker is not running. Please start Docker Desktop.
    exit /b 1
)

:: Load .env file into environment
if exist ".env" (
    for /f "usebackq tokens=1,2 delims==" %%a in (`findstr /v "^#\|^$" .env`) do (
        set "%%a=%%b"
    )
    echo ✅ .env variables loaded.
) else (
    echo ⚠️ .env file not found!
    exit /b 1
)

:: Create required folders
for %%d in (data logs cache init-db) do (
    if not exist %%d (
        mkdir %%d
        echo 📁 Created directory: %%d
    )
)

:: Create Docker volumes
for %%v in (mcp-data mcp-logs mcp-cache mcp-postgres-data) do (
    docker volume inspect %%v >nul 2>&1
    if errorlevel 1 (
        docker volume create %%v >nul
        echo 📦 Created volume: %%v
    )
)

:: Create Docker network if not exists
docker network inspect %MCP_NETWORK% >nul 2>&1
if errorlevel 1 (
    docker network create --subnet=%MCP_SUBNET% %MCP_NETWORK%
    echo 🌐 Created network: %MCP_NETWORK%
)

:: Generate secrets.yaml
set SECRETS_PATH=%USERPROFILE%\.docker\mcp\secrets.yaml
if not exist %USERPROFILE%\.docker\mcp (
    mkdir %USERPROFILE%\.docker\mcp
)

echo # MCP Secrets Configuration - Generated %DATE% > %SECRETS_PATH%
echo. >> %SECRETS_PATH%
echo github: >> %SECRETS_PATH%
echo   personal_access_token: "%GITHUB_TOKEN%" >> %SECRETS_PATH%
echo. >> %SECRETS_PATH%
echo gitlab: >> %SECRETS_PATH%
echo   personal_access_token: "%GITLAB_TOKEN%" >> %SECRETS_PATH%
echo. >> %SECRETS_PATH%
echo sentry: >> %SECRETS_PATH%
echo   auth_token: "%SENTRY_TOKEN%" >> %SECRETS_PATH%

echo 🔑 Generated secrets.yaml at %SECRETS_PATH%

:: Start Docker Compose
echo 🚀 Starting MCP stack...
docker-compose up -d

:: Delay then health check
timeout /t 8 >nul
curl http://localhost:8811/health && echo ✅ MCP is healthy! || echo ❌ MCP health check failed!


REM Detect dynamic ports via inspect (requires PowerShell or WSL for automation)
echo 🔍 Please run the following to find MCP/Traefik ports:
echo docker inspect -f "{{range $p, $conf := .NetworkSettings.Ports}}{{if eq $p "8811/tcp"}}{{(index $conf 0).HostPort}}{{end}}{{end}}" mcp-server
echo docker inspect -f "{{range $p, $conf := .NetworkSettings.Ports}}{{if eq $p "8080/tcp"}}{{(index $conf 0).HostPort}}{{end}}{{end}}" mcp-traefik
