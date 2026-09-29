$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
$buildExitCode = 1
try {
    # Native tools may write warnings to stderr; use their exit code.
    $ErrorActionPreference = 'Continue'
    & (Join-Path $PSScriptRoot 'build-rime-x64.cmd')
    $buildExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $buildExitCode
