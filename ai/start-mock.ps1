$ErrorActionPreference = 'Stop'
$python = Join-Path (Split-Path $PSScriptRoot -Parent) '.venv\Scripts\python.exe'
if (!(Test-Path $python)) { $python = (Get-Command python -ErrorAction Stop).Source }
Write-Host 'MOCK backend only. No model loaded. Ctrl+C stops it.'
& $python (Join-Path $PSScriptRoot 'scripts\mock_server.py')
exit $LASTEXITCODE