@echo off
:: Quick validation script to test PowerShell scripts
echo Testing PowerShell script syntax...

echo.
echo Testing firewall-manager.ps1...
pwsh -Command "& { try { . .\firewall-manager.ps1 -Check -ErrorAction Stop; Write-Host 'SUCCESS: firewall-manager.ps1 syntax is valid' -ForegroundColor Green } catch { Write-Host 'ERROR: firewall-manager.ps1 has syntax issues:' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red } }"

echo.
echo Testing port-scanner.ps1...
pwsh -Command "& { try { . .\port-scanner.ps1 -ErrorAction Stop; Write-Host 'SUCCESS: port-scanner.ps1 syntax is valid' -ForegroundColor Green } catch { Write-Host 'ERROR: port-scanner.ps1 has syntax issues:' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red } }"

echo.
echo Testing mcpconfig.ps1...
pwsh -Command "& { try { . .\mcpconfig.ps1 -ErrorAction Stop; Write-Host 'SUCCESS: mcpconfig.ps1 syntax is valid' -ForegroundColor Green } catch { Write-Host 'ERROR: mcpconfig.ps1 has syntax issues:' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red } }"

echo.
echo Script validation complete.
pause
