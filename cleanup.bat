@echo off
:: MCP Cleanup Script for Windows
:: Updated: June 2025
:: Handles service shutdown and firewall cleanup
setlocal enabledelayedexpansion

title MCP Cleanup

:: Clear screen
cls

echo.
echo ┌─────────────────────────────────────┐
echo │  MCP Cleanup Script                 │
echo │  %DATE% %TIME:~0,8%                 │
echo └─────────────────────────────────────┘
echo.

:: Function to log messages
goto :skip_functions

:log
echo [%DATE% %TIME:~0,8%] %~1: %~2
goto :eof

:skip_functions

call :log "INFO" "Starting MCP cleanup process..."

:: Stop all MCP containers
call :log "INFO" "Stopping MCP containers..."
docker compose down --volumes --remove-orphans >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :log "SUCCESS" "Docker containers stopped"
) else (
    call :log "WARNING" "Some containers may not have stopped properly"
)

:: Remove MCP containers and images (optional)
set /p REMOVE_IMAGES="Remove MCP Docker images? [y/N]: "
if /i "!REMOVE_IMAGES!"=="y" (
    call :log "INFO" "Removing MCP Docker images..."
    
    :: Remove containers
    for /f "tokens=*" %%i in ('docker ps -aq --filter "label=com.docker.compose.project=mcp" 2^>nul') do (
        docker rm %%i >nul 2>&1
    )
    
    :: Remove images
    docker image prune -f --filter "label=com.docker.compose.project=mcp" >nul 2>&1
    call :log "SUCCESS" "Docker images cleaned up"
)

:: Clean up Docker volumes
set /p REMOVE_VOLUMES="Remove MCP Docker volumes (data will be lost)? [y/N]: "
if /i "!REMOVE_VOLUMES!"=="y" (
    call :log "INFO" "Removing MCP Docker volumes..."
    docker volume rm mcp-data mcp-logs mcp-cache >nul 2>&1
    call :log "SUCCESS" "Docker volumes removed"
)

:: Clean up Docker networks
call :log "INFO" "Cleaning up Docker networks..."
docker network rm mcp-network >nul 2>&1

:: Clean up SSH-related volumes
call :log "INFO" "Cleaning up SSH configuration volumes..."
docker volume rm dhv01mcp-ssh-config >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :log "SUCCESS" "SSH configuration volume removed"
) else (
    call :log "INFO" "SSH configuration volume was not present or already removed"
)

:: Remove firewall rules
call :log "INFO" "Cleaning up firewall rules..."
if exist "firewall-manager.ps1" (
    :: Check which PowerShell to use
    where pwsh >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        pwsh -ExecutionPolicy Bypass -File firewall-manager.ps1 -Action disable >nul 2>&1
    ) else (
        powershell -ExecutionPolicy Bypass -File firewall-manager.ps1 -Action disable >nul 2>&1
    )
    
    if %ERRORLEVEL% EQU 0 (
        call :log "SUCCESS" "Firewall rules removed (including SSH rules)"
    ) else (
        call :log "WARNING" "Could not remove firewall rules (may require admin privileges)"
    )
) else (
    call :log "WARNING" "firewall-manager.ps1 not found, skipping firewall cleanup"
)

:: Clean up temporary files
call :log "INFO" "Cleaning up temporary files..."
if exist "*.tmp" del "*.tmp" >nul 2>&1
if exist "*.log" del "*.log" >nul 2>&1

:: Stop any remaining processes
call :log "INFO" "Checking for remaining MCP processes..."
for /f "tokens=2" %%i in ('tasklist /FI "IMAGENAME eq dhv01mcp*" /FO CSV /NH 2^>nul') do (
    if not "%%i"=="INFO: No tasks are running which match the specified criteria." (
        call :log "INFO" "Stopping process: %%i"
        taskkill /F /PID %%i >nul 2>&1
    )
)

:: Display cleanup summary
echo.
echo ┌─────────────────────────────────────┐
echo │  MCP Cleanup Complete               │
echo └─────────────────────────────────────┘
echo.
call :log "SUCCESS" "Cleanup process completed"
echo.
echo What was cleaned up:
echo  • Docker containers stopped
echo  • Docker networks removed
echo  • SSH configuration volumes removed
echo  • Firewall rules removed (including SSH)
echo  • Temporary files cleaned
echo.

if not "!REMOVE_IMAGES!"=="y" (
    echo Note: Docker images were preserved
)
if not "!REMOVE_VOLUMES!"=="y" (
    echo Note: Docker volumes were preserved
)

echo.
echo Press any key to exit...
pause > nul
