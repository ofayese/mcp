@echo off
:: MCP Health Check Script for Windows
:: Updated: June 2025
setlocal enabledelayedexpansion

:: Required environment variables
set "REQUIRED_VARS=MCP_HOST MCP_PORT"

:: Load .env file if it exists
if exist ".env" (
    echo [INFO] Loading environment variables from .env
    set ENV_COUNT=0
    
    for /f "usebackq tokens=1,2 delims==" %%a in (`findstr /v "^#\|^$" .env`) do (
        set "%%a=%%b"
        set /a ENV_COUNT+=1
    )
    echo [INFO] Loaded %ENV_COUNT% environment variables
)

:: Set default values for missing variables
if "%MCP_HOST%"=="" set "MCP_HOST=localhost"
if "%MCP_PORT%"=="" set "MCP_PORT=8811"

:: Configuration
set "HEALTH_URL=http://%MCP_HOST%:%MCP_PORT%/health"
set "TOOLS_URL=http://%MCP_HOST%:%MCP_PORT%/tools"
set "METRICS_URL=http://%MCP_HOST%:%MCP_PORT%/metrics"

echo.
echo ====================================
echo 🔍 MCP HEALTH CHECK - %DATE% %TIME%
echo ====================================
echo.

echo INFO: Environment: MCP_HOST=%MCP_HOST%, MCP_PORT=%MCP_PORT%
echo.

:: Check if PowerShell Core is available
where pwsh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: PowerShell Core (pwsh) is required but not installed.
    exit /b 1
)

:: Check MCP server health
echo INFO: Checking MCP server health at %HEALTH_URL%...
pwsh -Command "try { $r = Invoke-WebRequest -Uri '%HEALTH_URL%' -UseBasicParsing; if ($r.StatusCode -eq 200) { Write-Host 'SUCCESS: MCP server is healthy'; Write-Host ('  Response: ' + $r.Content); exit 0 } else { Write-Host 'ERROR: MCP server returned status: ' $r.StatusCode; exit 1 } } catch { Write-Host 'ERROR: MCP server not responding'; Write-Host ('  Error: ' + $_.Exception.Message); exit 1 }"
set HEALTH_CHECK=%ERRORLEVEL%

:: Check Docker connectivity
echo INFO: Checking Docker connectivity...
docker info >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo SUCCESS: Docker is accessible
    
    :: Check running MCP containers
    for /f "tokens=*" %%a in ('docker ps --filter "name=mcp" --format "{{.Names}}" 2^>nul') do (
        set "CONTAINERS=!CONTAINERS!%%a "
    )
    
    if defined CONTAINERS (
        echo SUCCESS: MCP containers running:
        for %%a in (%CONTAINERS%) do echo   - %%a
    ) else (
        echo WARNING: No MCP containers found running
    )
) else (
    echo WARNING: Docker is not accessible or not installed
)

:: Check MCP tools endpoint
echo INFO: Checking MCP tools at %TOOLS_URL%...
pwsh -Command "try { $r = Invoke-WebRequest -Uri '%TOOLS_URL%' -UseBasicParsing; if ($r.StatusCode -eq 200) { Write-Host 'SUCCESS: MCP tools are accessible'; Write-Host ('  Tools available: ' + ($r.Content | Select-String -Pattern '\"name\"' -AllMatches).Matches.Count); exit 0 } else { exit 1 } } catch { Write-Host 'WARNING: MCP tools endpoint not available'; exit 1 }"

:: Check MCP metrics endpoint
echo INFO: Checking MCP metrics at %METRICS_URL%...
pwsh -Command "try { $r = Invoke-WebRequest -Uri '%METRICS_URL%' -Method Head -UseBasicParsing; if ($r.StatusCode -eq 200) { Write-Host 'SUCCESS: MCP metrics endpoint is accessible'; exit 0 } else { exit 1 } } catch { Write-Host 'WARNING: MCP metrics endpoint not available'; exit 1 }"

:: Check Redis if possible
echo INFO: Checking Redis connection...
docker exec mcp-redis redis-cli -a "mcp" ping >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo SUCCESS: Redis is responsive
) else (
    echo WARNING: Redis check failed ^(may not be directly accessible^)
)

:: Check PostgreSQL if possible
echo INFO: Checking PostgreSQL connection...
docker exec mcp-postgres pg_isready -U mcp >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo SUCCESS: PostgreSQL is responsive
) else (
    echo WARNING: PostgreSQL check failed ^(may not be directly accessible^)
)

echo.
echo ====================================
if %HEALTH_CHECK% EQU 0 (
    echo 🎉 All critical health checks passed!
) else (
    echo 💥 Some health checks failed!
    echo See details above for troubleshooting.
)
echo ====================================
echo.

exit /b %HEALTH_CHECK%
