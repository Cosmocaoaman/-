$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\dev-environment.ps1')
$python = Resolve-DevPython -Root $root
Write-Host 'MOCK backend only. No model loaded. Ctrl+C stops it.'
& $python (Join-Path $PSScriptRoot 'scripts\mock_server.py')
exit $LASTEXITCODE
