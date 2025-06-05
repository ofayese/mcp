@echo off
:: MCP Quick Setup Script for Windows
:: Updated: June 2025
setlocal enabledelayedexpansion

:: Set console code page to UTF-8 for emoji support
chcp 65001 > nul 2>&1

:: Set title
title MCP Quick Setup

:: Clear screen
cls

:: Get start time
set START_TIME=%TIME%

echo ┌─────────────────────────────────────┐
echo │  MCP Quick Setup - Windows          │
echo │  %DATE% %TIME:~0,8%                 │
echo └─────────────────────────────────────┘
echo.

:: Check PowerShell version
powershell -Command "$Host.Version.Major" > temp.txt
set /p PS_VERSION=<temp.txt
del temp.txt

if %PS_VERSION% LSS 5 (
  echo [WARNING] PowerShell version is below 5.1. Some features may not work correctly.
  echo [WARNING] Consider upgrading PowerShell for better compatibility.
  echo.
)

echo [INFO] Checking Docker status...

:: Check if Docker is running
docker info > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo [ERROR] Docker is not running! Please start Docker Desktop first.
  echo.
  echo Press any key to exit...
  pause > nul
  exit /b 1
)

echo [SUCCESS] Docker is running

:: Verify Docker Compose is available
where docker-compose > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo [INFO] Checking for Docker Compose plugin...
  docker compose version > nul 2>&1
  if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Neither docker-compose nor Docker Compose plugin found.
    echo [WARNING] MCP setup may fail if Docker Compose is not available.
  ) else (
    echo [INFO] Docker Compose plugin is available.
  )
) else (
  echo [SUCCESS] docker-compose is available.
)

:: Check for prerequisites
echo.
echo [INFO] Checking prerequisites...
echo [INFO] - Directories
echo [INFO] - Network configuration
echo [INFO] - Docker volumes

:: Create secrets directory if it doesn't exist
if not exist "secrets" (
  echo [INFO] Creating secrets directory...
  mkdir secrets > nul 2>&1
  if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Failed to create secrets directory.
  ) else (
    echo [SUCCESS] Created secrets directory.
  )
)

:: Run the PowerShell configuration script
echo.
echo [INFO] Running MCP configuration...
echo [INFO] This might take a few minutes. Please wait...
echo.

powershell -ExecutionPolicy Bypass -File mcpconfig.ps1

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
echo [INFO] Running detailed health check...
echo.

call health-check.bat

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
echo For troubleshooting, use: 'docker logs mcp-server'
echo.
echo Press any key to exit...
pause > nul
