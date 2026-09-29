$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\dev-environment.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('rime-dev-test-' + [guid]::NewGuid().ToString('N'))
function AssertEqual($actual, $expected) { if ($actual -ne $expected) { throw "Expected '$expected', got '$actual'" } }
function AssertThrows([scriptblock]$action) {
    $threw = $false
    try { & $action | Out-Null } catch { $threw = $true }
    if (!$threw) { throw 'Expected rejection.' }
}
try {
    $one = Join-Path $fixture 'First installation'
    $two = Join-Path $fixture 'Second installation'
    foreach ($path in @($one,$two)) {
        New-Item -ItemType Directory -Force $path | Out-Null
        [IO.File]::WriteAllText((Join-Path $path 'WeaselServer.exe'), 'fixture only')
    }
    AssertEqual (Select-WeaselInstallation -ExplicitPath $one) $one
    AssertEqual (Select-WeaselInstallation -RunningPaths @($two) -CandidatePaths @($one)) $two
    AssertEqual (Select-WeaselInstallation -CandidatePaths @($one,$one)) $one
    AssertEqual (Select-WeaselInstallation -RunningPaths @($one,$one)) $one
    AssertEqual (Select-WeaselInstallation -CandidatePaths @((Join-Path $fixture 'missing'),$one)) $one
    AssertEqual (Select-WeaselInstallation -ExplicitPath $two -CandidatePaths @($one,$two)) $two
    AssertThrows { Select-WeaselInstallation -CandidatePaths @($one,$two) }
    AssertThrows { Select-WeaselInstallation -RunningPaths @($one,$two) }
    AssertThrows { Select-WeaselInstallation }
    AssertThrows { Select-WeaselInstallation -ExplicitPath $fixture }
    Write-Host 'PASS: 10 installation-selection cases; no real installation changed.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or !(Split-Path $resolved -Leaf).StartsWith('rime-dev-test-')) { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
