@echo off
:: MCP Reset and Recovery Script
:: Use this if setup.bat gets stuck or needs to be reset
setlocal enabledelayedexpansion

echo.
echo ┌─────────────────────────────────────┐
echo │  MCP Reset and Recovery             │
echo │  %DATE% %TIME:~0,8%                 │
echo └─────────────────────────────────────┘
echo.

echo [%TIME:~0,8%] INFO: Stopping any running setup processes...

:: Kill any hanging Docker processes
taskkill /F /IM docker.exe >nul 2>&1
taskkill /F /IM "Docker Desktop.exe" >nul 2>&1

echo [%TIME:~0,8%] INFO: Cleaning up Docker resources...

:: Stop all MCP containers
docker compose down >nul 2>&1

:: Note: MCP uses host networking exclusively, no custom networks to clean
echo [%TIME:~0,8%] INFO: Host networking mode - no custom networks to remove

echo [%TIME:~0,8%] SUCCESS: Cleanup completed

echo.
echo Ready to run setup again. Choose an option:
echo.
echo 1. Run setup.bat (full setup)
echo 2. Run setup.bat -q (quick mode)
echo 3. Exit and run setup manually
echo.
set /p CHOICE="Enter choice [1-3]: "

if "%CHOICE%"=="1" (
    echo [%TIME:~0,8%] INFO: Starting full setup...
    call setup.bat
) else if "%CHOICE%"=="2" (
    echo [%TIME:~0,8%] INFO: Starting quick setup...
    call setup.bat -q
) else (
    echo [%TIME:~0,8%] INFO: Exiting. Run 'setup.bat' when ready.
)

echo.
echo Press any key to exit...
pause > nul
