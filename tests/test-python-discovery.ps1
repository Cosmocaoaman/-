$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\dev-environment.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('rime-python-test-' + [guid]::NewGuid().ToString('N'))
try {
    $base = Resolve-DevPython -Root $root -Base
    $explicit = Resolve-DevPython -Root $root -Python $base
    if ($explicit -ne $base) { throw 'Explicit Python selection failed' }
    $venv = Join-Path $root '.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $venv) {
        if ((Resolve-DevPython -Root $root) -ne $venv) { throw 'Project venv was not preferred' }
        if ((Resolve-DevPython -Root $root -Python $venv -Base) -ne $base) { throw 'Base interpreter resolution failed' }
    }
    # A stale/unusable venv must not prevent discovery through py or PATH.
    $scripts = Join-Path $fixture '.venv\Scripts'
    New-Item -ItemType Directory -Force $scripts | Out-Null
    Set-Content -LiteralPath (Join-Path $scripts 'python.exe') -Value 'Invalid executable fixture'
    if ((Resolve-DevPython -Root $fixture) -ne $base) { throw 'Broken venv fallback failed' }
    $rejected = $false
    try { Resolve-DevPython -Root $fixture -Python (Join-Path $scripts 'python.exe') | Out-Null } catch { $rejected = $true }
    if (!$rejected) { throw 'Explicit invalid interpreter was accepted' }
    Write-Host 'PASS: Python selection, base discovery, broken venv recovery, and explicit failure.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or !(Split-Path $resolved -Leaf).StartsWith('rime-python-test-')) { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
