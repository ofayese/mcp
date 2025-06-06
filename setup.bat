@echo off
:: MCP Unified Setup Script for Windows
:: Updated: June 2025
:: Combines functionality of setup.bat and quick-setup.bat
setlocal enabledelayedexpansion

:: Set console code page to UTF-8 for emoji support
chcp 65001 > nul 2>&1

:: Parse command line arguments
set "QUICK_MODE=false"
set "SKIP_CHECKS=false"

:parse_args
if "%~1"=="" goto :end_parse_args
if /i "%~1"=="-q" set "QUICK_MODE=true" & goto :next_arg
if /i "%~1"=="--quick" set "QUICK_MODE=true" & goto :next_arg
if /i "%~1"=="-y" set "SKIP_CHECKS=true" & goto :next_arg
if /i "%~1"=="--yes" set "SKIP_CHECKS=true" & goto :next_arg
if /i "%~1"=="-h" goto :show_help
if /i "%~1"=="--help" goto :show_help
echo Unknown parameter: %~1
goto :show_help

:next_arg
shift
goto :parse_args

:show_help
echo.
echo MCP Setup Script - Usage:
echo setup.bat [options]
echo.
echo Options:
echo   -q, --quick    Quick setup mode (skips some confirmations)
echo   -y, --yes      Skip all confirmations and checks
echo   -h, --help     Show this help message
echo.
exit /b 0

:end_parse_args

:: Set title based on mode
if "%QUICK_MODE%"=="true" (
    title MCP Quick Setup
) else (
    title MCP Secure Setup
)

:: Clear screen
cls

:: Get start time
set START_TIME=%TIME%

:: Script constants
set "REQUIRED_DIRS=data logs cache init-db secrets"
set "REQUIRED_VOLUMES=mcp-data mcp-logs mcp-cache"
set "MCP_NETWORK=mcp-network"
set "MCP_SUBNET=172.40.1.0/24"
set "HEALTH_CHECK_URL=http://localhost:8811/health"
set "HEALTH_CHECK_TIMEOUT=30"

:: Header
echo.
if "%QUICK_MODE%"=="true" (
    echo ┌─────────────────────────────────────┐
    echo │  MCP Quick Setup - Windows          │
    echo │  %DATE% %TIME:~0,8%                 │
    echo └─────────────────────────────────────┘
) else (
    echo ┌─────────────────────────────────────┐
    echo │  MCP Secure Setup - Windows         │
    echo │  %DATE% %TIME:~0,8%                 │
    echo └─────────────────────────────────────┘
)
echo.

:: Function to log messages
goto :skip_functions

:log
echo [%DATE% %TIME:~0,8%] %~1: %~2
goto :eof

:skip_functions

:: Check PowerShell version
for /f "tokens=*" %%i in ('pwsh -Command "$Host.Version.Major" 2^>nul') do set PS_VERSION=%%i
if not defined PS_VERSION (
    for /f "tokens=*" %%i in ('powershell -Command "$Host.Version.Major" 2^>nul') do set PS_VERSION=%%i
)

if not defined PS_VERSION (
    call :log "ERROR" "PowerShell is not available. Please install PowerShell."
    exit /b 1
)

if %PS_VERSION% LSS 5 (
    call :log "WARNING" "PowerShell version is below 5.1. Some features may not work correctly."
    call :log "WARNING" "Consider upgrading PowerShell for better compatibility."
    echo.
)

:: Check Docker availability
call :log "INFO" "Checking Docker status..."
docker info >nul 2>&1
if errorlevel 1 (
    call :log "ERROR" "Docker is not running. Please start Docker Desktop."
    exit /b 1
) else (
    call :log "SUCCESS" "Docker is running"
)

:: Verify Docker Compose is available
where docker-compose > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    call :log "INFO" "Checking for Docker Compose plugin..."
    docker compose version > nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        call :log "WARNING" "Neither docker-compose nor Docker Compose plugin found."
        call :log "WARNING" "MCP setup may fail if Docker Compose is not available."
    ) else (
        call :log "INFO" "Docker Compose plugin is available."
    )
) else (
    call :log "SUCCESS" "docker-compose is available."
)

:: Prompt for confirmation in full mode
if "%QUICK_MODE%"=="false" (
    if "%SKIP_CHECKS%"=="false" (
        echo.
        echo This script will:
        echo  • Set up Docker volumes and networks
        echo  • Create required directories with secure permissions
        echo  • Configure environment variables
        echo  • Start MCP containers
        echo.
        set /p CONFIRM="Continue with setup? [Y/n]: "
        if /i "!CONFIRM!"=="n" (
            echo Setup cancelled by user.
            exit /b 0
        )
    )
)

:: Load .env file into environment
if exist ".env" (
    call :log "INFO" "Loading environment variables from .env"
    set ENV_COUNT=0
    
    for /f "usebackq tokens=1,2 delims==" %%a in (`findstr /v "^#\|^$" .env`) do (
        set "%%a=%%b"
        set /a ENV_COUNT+=1
    )
    call :log "SUCCESS" "Loaded !ENV_COUNT! environment variables"
) else (
    call :log "WARNING" "'.env' file not found, using default values"
)

:: Check required environment variables
call :log "INFO" "Checking required environment variables..."
set "MISSING_VARS="
set "REQUIRED_VARS=COMPOSE_PROJECT_NAME COMPOSE_FILE MCP_HOST MCP_PORT MCP_NETWORK MCP_SUBNET MCP_DATA_DIR MCP_CACHE_DIR MCP_CONFIG_PATH MCP_SECRETS_PATH MCP_REGISTRY_PATH POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD REDIS_PASSWORD"

for %%v in (%REQUIRED_VARS%) do (
    if not defined %%v (
        set "MISSING_VARS=!MISSING_VARS! %%v"
    )
)

if defined MISSING_VARS (
    call :log "ERROR" "Missing required environment variables: !MISSING_VARS!"
    if "%SKIP_CHECKS%"=="false" (
        call :log "ERROR" "Please check your .env file and try again."
        exit /b 1
    ) else (
        call :log "WARNING" "Continuing despite missing variables because --yes was specified."
    )
)

:: Create required folders with improved security
call :log "INFO" "Setting up directories..."
for %%d in (%REQUIRED_DIRS%) do (
    if not exist %%d (
        mkdir %%d
        call :log "INFO" "Created directory: %%d"
        
        :: Set proper permissions (Windows equivalent of chmod 750)
        icacls %%d /inheritance:r /grant:r "%USERNAME%:(OI)(CI)(F)" /grant "SYSTEM:(OI)(CI)(F)" >nul
        if errorlevel 0 (
            call :log "SUCCESS" "Secured directory permissions: %%d"
        ) else (
            call :log "WARNING" "Could not set secure permissions on %%d"
        )
    ) else (
        call :log "SUCCESS" "Directory exists: %%d"
    )
)

:: Create Docker volumes
call :log "INFO" "Setting up Docker volumes..."
for %%v in (%REQUIRED_VOLUMES%) do (
    docker volume inspect %%v >nul 2>&1
    if errorlevel 1 (
        docker volume create %%v >nul
        call :log "SUCCESS" "Created volume: %%v"
    ) else (
        call :log "SUCCESS" "Volume exists: %%v"
    )
)

:: Create Docker network if not exists
call :log "INFO" "Setting up Docker network..."
if defined MCP_NETWORK (
    docker network inspect %MCP_NETWORK% >nul 2>&1
    if errorlevel 1 (
        if defined MCP_SUBNET (
            docker network create --subnet=%MCP_SUBNET% %MCP_NETWORK% >nul
            call :log "SUCCESS" "Created network: %MCP_NETWORK% (%MCP_SUBNET%)"
        ) else (
            docker network create %MCP_NETWORK% >nul
            call :log "SUCCESS" "Created network: %MCP_NETWORK%"
        )
    ) else (
        call :log "SUCCESS" "Network exists: %MCP_NETWORK%"
    )
) else (
    call :log "WARNING" "MCP_NETWORK not defined, using default network"
)

:: Set up secrets from environment variables
call :log "INFO" "Setting up secrets..."

:: Create secrets directory if it doesn't exist
if not exist "secrets" (
    mkdir secrets
    call :log "INFO" "Created secrets directory"
)

:: GitHub token
if defined GITHUB_TOKEN (
    echo %GITHUB_TOKEN%> secrets\github.personal_access_token
    call :log "SUCCESS" "Created GitHub token file"
)

:: GitHub Personal Access Token
if defined GITHUB_PAT (
    echo %GITHUB_PAT%> secrets\github.personal_access_token
    call :log "SUCCESS" "Created GitHub PAT file"
)

:: GitLab token
if defined GITLAB_TOKEN (
    echo %GITLAB_TOKEN%> secrets\gitlab.personal_access_token
    call :log "SUCCESS" "Created GitLab token file"
)

:: Sentry token
if defined SENTRY_TOKEN (
    echo %SENTRY_TOKEN%> secrets\sentry.auth_token
    call :log "SUCCESS" "Created Sentry token file"
)

:: GitHub Chat API key
if defined GITHUB_CHAT_API_KEY (
    echo %GITHUB_CHAT_API_KEY%> secrets\github-chat.api_key
    call :log "SUCCESS" "Created GitHub Chat API key file"
)

:: PostgreSQL password
if defined POSTGRES_PASSWORD (
    echo %POSTGRES_PASSWORD%> secrets\postgres_password.txt
    call :log "SUCCESS" "Created PostgreSQL password file"
)

call :log "INFO" "Secrets setup complete"

:: Run the PowerShell configuration script
echo.
call :log "INFO" "Running MCP configuration..."
if "%QUICK_MODE%"=="true" (
    call :log "INFO" "Using quick mode - this might take a few minutes. Please wait..."
) else (
    call :log "INFO" "Using secure mode - this might take several minutes. Please wait..."
)
echo.

:: Check which PowerShell to use
where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh -ExecutionPolicy Bypass -File mcpconfig.ps1
) else (
    powershell -ExecutionPolicy Bypass -File mcpconfig.ps1
)

:: Calculate configuration duration
for /F "tokens=1-4 delims=:.," %%a in ("%START_TIME%") do (
  set /A "start=(((%%a*60)+1%%b %% 100)*60+1%%c %% 100)*100+1%%d %% 100"
)
for /F "tokens=1-4 delims=:.," %%a in ("%TIME%") do (
  set /A "end=(((%%a*60)+1%%b %% 100)*60+1%%c %% 100)*100+1%%d %% 100"
)
set /A elapsed=end-start
set /A hh=elapsed/(60*60*100), rest=elapsed%%(60*60*100), mm=rest/(60*100), rest%%=60*100, ss=rest/100
if %hh% lss 10 set hh=0%hh%
if %mm% lss 10 set mm=0%mm%
if %ss% lss 10 set ss=0%ss%

:: Run detailed health check
echo.
call :log "INFO" "Running detailed health check..."
echo.

if exist "health-check.bat" (
    call health-check.bat
) else (
    call :log "WARNING" "health-check.bat not found. Skipping detailed health check."
)

echo.
echo ┌─────────────────────────────────────┐
echo │  MCP Setup Complete                 │
echo │  Time: %hh%:%mm%:%ss%                      │
echo └─────────────────────────────────────┘
echo.
echo Access Points:
echo  • MCP Server: http://localhost:8811
echo  • Traefik Dashboard: http://localhost:8080
echo.
echo For troubleshooting, use: 'docker logs dhv01mcp'
echo.

if "%QUICK_MODE%"=="false" (
    echo Press any key to exit...
    pause > nul
)
