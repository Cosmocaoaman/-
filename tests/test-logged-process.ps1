$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\logged-process.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('rime-process-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture | Out-Null
try {
    $child = Join-Path $fixture 'child.ps1'
    @'
param([string]$Mode)
if ($Mode -eq 'timeout') { Start-Sleep -Seconds 10; exit 0 }
for ($i = 0; $i -lt 2000; $i++) {
    [Console]::Out.WriteLine("stdout-$i")
    [Console]::Error.WriteLine("stderr-$i")
}
if ($Mode -eq 'fail') { exit 7 }
exit 0
'@ | Set-Content -LiteralPath $child -Encoding UTF8
    $parameters = @{ FilePath='powershell.exe'; WorkingDirectory=$fixture; LogDirectory=$fixture }
    Invoke-LoggedProcess @parameters -ArgumentList @('-NoProfile','-File', ('"' + $child + '"')) -Label 'success' 6>$null
    foreach ($stream in @('out','err')) {
        $lines = @(Get-Content -LiteralPath (Join-Path $fixture "success.$stream.log"))
        if ($lines.Count -ne 2000 -or $lines[-1] -notmatch '1999$') { throw "Lost $stream output" }
    }
    $failure = ''
    try { Invoke-LoggedProcess @parameters -ArgumentList @('-NoProfile','-File', ('"' + $child + '"'), '-Mode','fail') -Label 'failure' 6>$null } catch { $failure = $_.ToString() }
    if ($failure -notmatch 'exit 7') { throw 'Nonzero exit was not reported' }
    $failure = ''
    try { Invoke-LoggedProcess @parameters -ArgumentList @('-NoProfile','-File', ('"' + $child + '"'), '-Mode','timeout') -Label 'timeout' -TimeoutMilliseconds 300 6>$null } catch { $failure = $_.ToString() }
    if ($failure -notmatch 'timed out') { throw 'Timeout was not reported' }
    Write-Host 'PASS: concurrent stdout/stderr (4000 lines), nonzero exit, and timeout.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or !(Split-Path $resolved -Leaf).StartsWith('rime-process-test-')) { throw 'Unsafe fixture cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
