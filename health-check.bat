@echo off
setlocal
set HOST=localhost
set PORT=8811
set URL=http://%HOST%:%PORT%/health

echo Checking MCP server health at %URL% ...
powershell -Command "try { $r = Invoke-WebRequest -Uri '%URL%' -UseBasicParsing; if ($r.StatusCode -eq 200) { Write-Host '✅ MCP server is healthy'; exit 0 } else { Write-Host '❌ MCP server returned status: ' $r.StatusCode; exit 1 } } catch { Write-Host '❌ MCP server not responding'; exit 1 }"
