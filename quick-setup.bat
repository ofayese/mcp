@echo off
echo 🔧 Setting up MCP environment...

REM Check if Docker is running
docker info > nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo ❌ Docker is not running! Please start Docker Desktop first.
  exit /b 1
)

REM Run the PowerShell configuration script
echo 🚀 Running MCP configuration...
powershell -ExecutionPolicy Bypass -File mcpconfig.ps1

REM Run detailed health check
echo 🩺 Running detailed health check...
call health-check.bat

echo ✅ MCP setup complete!
echo.
echo 📊 You can access:
echo  - MCP Server: http://localhost:8811
echo  - Traefik Dashboard: http://localhost:8080
