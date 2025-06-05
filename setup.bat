@echo off
:: MCP Secure Setup Script for Windows
:: Updated: June 2025
setlocal enabledelayedexpansion

:: Set console code page to UTF-8 for emoji support
chcp 65001 > nul 2>&1

:: Set title
title MCP Secure Setup

:: Script constants
set "REQUIRED_DIRS=data logs cache init-db secrets"
set "REQUIRED_VOLUMES=mcp-data mcp-logs mcp-cache"
set "MCP_NETWORK=mcp-network"
set "MCP_SUBNET=172.40.1.0/24"
set "HEALTH_CHECK_URL=http://localhost:8811/health"
set "HEALTH_CHECK_TIMEOUT=30"

:: Header
echo.
echo ┌─────────────────────────────────────┐
echo │  MCP Secure Setup - Windows         │
echo │  %DATE% %TIME:~0,8%                 │
echo └─────────────────────────────────────┘
echo.

:: Functions
:log
echo [%~1] %~2
goto :eof

:: Check PowerShell version
powershell -Command "$Host.Version.Major" > temp.txt
set /p PS_VERSION=<temp.txt
del temp.txt

if %PS_VERSION% LSS 5 (
    call :log WARNING "PowerShell version is below 5.1. Some features may not work correctly."
    call :log WARNING "Consider upgrading PowerShell for better compatibility."
    echo.
)

:: Check Docker availability
call :log INFO "Checking Docker status..."
docker info >nul 2>&1
if errorlevel 1 (
    call :log ERROR "Docker is not running. Please start Docker Desktop."
    exit /b 1
) else (
    call :log SUCCESS "Docker is running"
)

:: Load .env file into environment
if exist ".env" (
    call :log INFO "Loading environment variables from .env"
    set ENV_COUNT=0
    
    for /f "usebackq tokens=1,2 delims==" %%a in (`findstr /v "^#\|^$" .env`) do (
        set "%%a=%%b"
        set /a ENV_COUNT+=1
    )
    call :log SUCCESS "Loaded %ENV_COUNT% environment variables"
) else (
    call :log WARNING "'.env' file not found, using default values"
)

:: Create required folders with improved security
call :log INFO "Setting up directories..."
for %%d in (%REQUIRED_DIRS%) do (
    if not exist %%d (
        mkdir %%d
        call :log INFO "Created directory: %%d"
        
        :: Set proper permissions (Windows equivalent of chmod 750)
        icacls %%d /inheritance:r /grant:r "%USERNAME%:(OI)(CI)(F)" /grant "SYSTEM:(OI)(CI)(F)" >nul
        if errorlevel 0 (
            call :log SUCCESS "Secured directory permissions: %%d"
        ) else (
            call :log WARNING "Could not set secure permissions on %%d"
        )
    ) else (
        call :log SUCCESS "Directory exists: %%d"
    )
)

:: Create Docker volumes
call :log INFO "Setting up Docker volumes..."
for %%v in (%REQUIRED_VOLUMES%) do (
    docker volume inspect %%v >nul 2>&1
    if errorlevel 1 (
        docker volume create %%v >nul
        call :log SUCCESS "Created volume: %%v"
    ) else (
        call :log SUCCESS "Volume exists: %%v"
    )
)

:: Create Docker network if not exists
call :log INFO "Setting up Docker network..."
if defined MCP_NETWORK (
    docker network inspect %MCP_NETWORK% >nul 2>&1
    if errorlevel 1 (
        if defined MCP_SUBNET (
            docker network create --subnet=%MCP_SUBNET% %MCP_NETWORK% >nul
            call :log SUCCESS "Created network: %MCP_NETWORK% (%MCP_SUBNET%)"
        ) else (
            docker network create %MCP_NETWORK% >nul
            call :log SUCCESS "Created network: %MCP_NETWORK%"
        )
    ) else (
        call :log SUCCESS "Network exists: %MCP_NETWORK%"
    )
) else (
    call :log WARNING "MCP_NETWORK not defined, using default network"
)

:: Set up secrets from environment variables
call :log INFO "Setting up secrets..."

:: Create secrets directory if it doesn't exist
if not exist "secrets" (
    mkdir secrets
    call :log INFO "Created secrets directory"
)

:: GitHub token
if defined GITHUB_TOKEN (
    echo %GITHUB_TOKEN%> secrets\github_token
    call :log SUCCESS "Created GitHub token file"
)

:: GitHub Personal Access Token
if defined GITHUB_PAT (
    echo %GITHUB_PAT%> secrets\github.personal_access_token
    call :log SUCCESS "Created GitHub PAT file"
)

:: GitLab token
if defined GITLAB_TOKEN (
    echo %GITLAB_TOKEN%> secrets\gitlab_token
    call :log SUCCESS "Created GitLab token file"
)

:: Sentry token
if defined SENTRY_TOKEN (
    echo %SENTRY_TOKEN%> secrets\sentry_token
    call :log SUCCESS "Created Sentry token file"
)

:: GitHub Chat API key
if defined GITHUB_CHAT_API_KEY (
    echo %GITHUB_CHAT_API_KEY%> secrets\github-chat.api_key
    call :log SUCCESS "Created GitHub Chat API key file"
)

call :log INFO "Secrets setup complete"

:: Check Docker Compose availability
where docker-compose >nul 2>&1
if errorlevel 1 (
    call :log INFO "Checking for Docker Compose plugin..."
    docker compose version >nul 2>&1
    if errorlevel 1 (
        call :log WARNING "Neither docker-compose nor Docker Compose plugin found."
        call :log WARNING "MCP setup may fail if Docker Compose is not available."
        set COMPOSE_CMD=docker compose
    ) else (
        call :log INFO "Docker Compose plugin is available."
        set COMPOSE_CMD=docker compose
    )
) else (
    call :log SUCCESS "docker-compose is available."
    set COMPOSE_CMD=docker-compose
)

:: Start Docker Compose
call :log INFO "Starting MCP stack with %COMPOSE_CMD%..."
%COMPOSE_CMD% up -d

:: Wait and check health
call :log INFO "Waiting for services to initialize (%HEALTH_CHECK_TIMEOUT%s timeout)..."

set start_time=%time%
set healthy=false

:health_check_loop
for /f "tokens=1-4 delims=:.," %%a in ("%time%") do (
    set /a current=((1%%a %% 100)*3600 + (1%%b %% 100)*60 + (1%%c %% 100))*100 + (1%%d %% 100)
)
for /f "tokens=1-4 delims=:.," %%a in ("%start_time%") do (
    set /a start=((1%%a %% 100)*3600 + (1%%b %% 100)*60 + (1%%c %% 100))*100 + (1%%d %% 100)
)
set /a elapsed=(current-start)/100
if %elapsed% gtr %HEALTH_CHECK_TIMEOUT% goto :health_check_done

:: Check health
curl -s -f %HEALTH_CHECK_URL% >nul 2>&1
if errorlevel 1 (
    echo . 
    timeout /t 2 >nul
    goto :health_check_loop
) else (
    set healthy=true
    goto :health_check_done
)

:health_check_done
echo.
if "%healthy%"=="true" (
    call :log SUCCESS "MCP is healthy! (Time: %elapsed%s)"
) else (
    call :log WARNING "MCP health check timed out after %elapsed%s"
    call :log INFO "Run 'health-check.bat' to troubleshoot or check container logs"
)

:: Show container status
call :log INFO "MCP container status:"
docker ps --filter "name=mcp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo.
echo ┌─────────────────────────────────────┐
echo │  MCP Setup Complete                 │
echo └─────────────────────────────────────┘
echo.
echo Access Points:
echo  • MCP Server: http://localhost:8811
echo  • Traefik Dashboard: http://localhost:8080
echo.
echo For troubleshooting, use: 'docker logs mcp-server'
echo.
