param([Parameter(Mandatory=$true)][int]$ProcessId, [Parameter(Mandatory=$true)][string]$ExpectedDll)
$ErrorActionPreference = 'Stop'
# Run from 32-bit PowerShell to inspect the x86 Weasel process.
$process = Get-Process -Id $ProcessId
foreach ($module in $process.Modules) {
    if ([string]::Equals($module.FileName, $ExpectedDll, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Output $module.FileName
        exit 0
    }
}
Write-Error 'The expected Rime DLL was not loaded.'
exit 1
