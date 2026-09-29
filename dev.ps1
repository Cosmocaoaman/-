param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\RimeAI'),
    [switch]$StartMock
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$logDir = Join-Path $root "ai\logs\deploy-$stamp"
$mutex = New-Object Threading.Mutex($false, 'Local\RimeAI-Developer-Deploy')
$locked = $false
$needsRecovery = $false
$backup = $null
$newMock = $null
function RunningServers {
    @(Get-CimInstance Win32_Process -Filter "Name = 'WeaselServer.exe'")
}
function CheckServerPaths {
    foreach ($item in (RunningServers)) {
        if (!$item.ExecutablePath -or ![string]::Equals($item.ExecutablePath, $server, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Another or inaccessible Weasel installation is running. Close it first or specify its -InstallDir.'
        }
    }
}
function InvokeLogged([string]$file, [string[]]$arguments, [string]$label, [int]$timeout = 0) {
    # Weasel compares the entire raw command line to /q and /deploy.
    # Windows PowerShell Start-Process adds trailing whitespace; use exact arguments.
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $file
    $info.Arguments = [string]::Join(' ', $arguments).Trim()
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $null = $proc.Start()
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    if ($timeout -gt 0) {
        if (!$proc.WaitForExit($timeout)) { $proc.Kill(); $proc.WaitForExit(); throw "$label timed out. See $logDir" }
    } else { $proc.WaitForExit() }
    [IO.File]::WriteAllText((Join-Path $logDir "$label.out.log"), $stdout.GetAwaiter().GetResult())
    [IO.File]::WriteAllText((Join-Path $logDir "$label.err.log"), $stderr.GetAwaiter().GetResult())
    $code = $proc.ExitCode
    $proc.Dispose()
    if ($code -ne 0) { throw "$label failed (exit $code). See $logDir" }
}
function Machine([string]$file) {
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes.Length -lt 64) { throw "Not a PE file: $file" }
    $offset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($offset -lt 0 -or ($offset + 6) -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$offset) -ne 0x4550) { throw "Invalid PE: $file" }
    [BitConverter]::ToUInt16($bytes, $offset + 4)
}
function StopServer {
    CheckServerPaths
    if (@(RunningServers).Count -eq 0) { return }
    InvokeLogged $server @('/q') ('stop-' + [guid]::NewGuid().ToString('N')) 15000
    $deadline = (Get-Date).AddSeconds(15)
    while (@(RunningServers).Count -gt 0) {
        if ((Get-Date) -gt $deadline) { throw 'Weasel did not stop; no forced termination performed.' }
        Start-Sleep -Milliseconds 200
    }
}
function StartServer {
    CheckServerPaths
    if (@(RunningServers).Count -eq 0) { Start-Process -FilePath $server -WorkingDirectory $InstallDir -WindowStyle Hidden | Out-Null }
    Start-Sleep -Seconds 2
    CheckServerPaths
    if (@(RunningServers).Count -eq 0) { throw 'Weasel exited during startup.' }
    # A surviving process alone is insufficient: verify it actually loaded this DLL.
    foreach ($item in (RunningServers)) {
        $inspector = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
        InvokeLogged $inspector @('-NoProfile','-ExecutionPolicy','Bypass','-File', ('"' + (Join-Path $root 'scripts\check-loaded-engine.ps1') + '"'), '-ProcessId', [string]$item.ProcessId, '-ExpectedDll', ('"' + $installedDll + '"')) ('verify-' + [guid]::NewGuid().ToString('N')) 15000
    }
}
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (!$locked) { throw 'Another Rime AI deployment is already running.' }
    if (![Environment]::Is64BitProcess) { throw 'Run this script in 64-bit PowerShell.' }
    $InstallDir = (Resolve-Path -LiteralPath $InstallDir).Path
    $server = Join-Path $InstallDir 'WeaselServer.exe'
    $deployer = Join-Path $InstallDir 'WeaselDeployer.exe'
    $installedDll = Join-Path $InstallDir 'rime.dll'
    $installedSchema = Join-Path $InstallDir 'data\local_ai_pinyin.schema.yaml'
    $engine = Join-Path $root 'librime\dist-x86\lib\rime.dll'
    $schema = Join-Path $root 'ai\rime-data\local_ai_pinyin.schema.yaml'
    foreach ($file in @($server, $deployer, $installedDll, $installedSchema, $schema)) {
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing $file. This command updates an existing Rime AI installation; it does not install or register an IME." }
    }
    if ((Machine $server) -ne 0x14c -or (Machine $installedDll) -ne 0x14c) { throw 'This deployment command requires an x86 Weasel server and engine.' }
    CheckServerPaths
    $python = Join-Path $root '.venv\Scripts\python.exe'
    if (!(Test-Path $python)) { $python = (Get-Command python -ErrorAction Stop).Source }
    New-Item -ItemType Directory -Force $logDir | Out-Null
    Write-Host "Logs: $logDir"
    Write-Host '[1/5] Build x86 and run upstream tests...'
    InvokeLogged 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File', ('"' + (Join-Path $root 'build-rime-x86.ps1') + '"')) 'build'
    if ((Machine $engine) -ne 0x14c) { throw 'New engine is not x86.' }
    Write-Host '[2/5] Run isolated integration tests...'
    InvokeLogged $python @(('"' + (Join-Path $root 'ai\tests\run_integration.py') + '"'), '--arch','x86','--port','0') 'integration'
    if ($StartMock) {
        $client = New-Object Net.Sockets.TcpClient
        try { $client.Connect('127.0.0.1',18080); $listening = $true } catch { $listening = $false } finally { $client.Dispose() }
        if ($listening) { Write-Host 'Port 18080 already has a backend; leaving it running.' }
        else {
            $newMock = Start-Process -FilePath $python -ArgumentList @(('"' + (Join-Path $root 'ai\scripts\mock_server.py') + '"')) -WorkingDirectory $root -WindowStyle Hidden -PassThru `
                -RedirectStandardOutput (Join-Path $logDir 'mock.out.log') -RedirectStandardError (Join-Path $logDir 'mock.err.log')
            $ready = $false
            for ($i=0; $i -lt 30; $i++) {
                try { $health = Invoke-RestMethod 'http://127.0.0.1:18080/health' -TimeoutSec 1; if ($health.mode -eq 'mock') { $ready=$true; break } } catch { }
                Start-Sleep -Milliseconds 200
            }
            if (!$ready) { throw 'MOCK backend did not become ready.' }
        }
    }
    Write-Host '[3/5] Back up installed engine and AI schema...'
    $backup = Join-Path $InstallDir ".rime-ai-backups\$stamp"
    New-Item -ItemType Directory -Force $backup | Out-Null
    Copy-Item -LiteralPath $installedDll -Destination (Join-Path $backup 'rime.dll')
    Copy-Item -LiteralPath $installedSchema -Destination (Join-Path $backup 'local_ai_pinyin.schema.yaml')
    $oldHash = (Get-FileHash $installedDll).Hash
    Write-Host '[4/5] Restart input method with the new engine and redeploy AI schema...'
    $needsRecovery = $true
    StopServer
    Copy-Item -LiteralPath $engine -Destination $installedDll -Force
    Copy-Item -LiteralPath $schema -Destination $installedSchema -Force
    $newHash = (Get-FileHash $engine).Hash
    if ((Get-FileHash $installedDll).Hash -ne $newHash) { throw 'Installed DLL hash mismatch.' }
    InvokeLogged $deployer @('/deploy') 'schema-deploy' 120000
    StartServer
    [ordered]@{ time=(Get-Date).ToString('o'); source=$root; install=$InstallDir; backup=$backup; oldSha256=$oldHash; newSha256=$newHash; mockStartedPid=$(if ($newMock) {$newMock.Id} else {$null}) } |
        ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $logDir 'deployment.json')
    $needsRecovery = $false
    Write-Host '[5/5] Done. Existing Windows input-method selection is unchanged.'
    Write-Host "Backup: $backup"
    Write-Host "Manifest: $(Join-Path $logDir 'deployment.json')"
    if ($newMock) { Write-Host "MOCK (not a real model) started, PID $($newMock.Id)." }
} catch {
    $failure = $_
    if ($needsRecovery) {
        try {
            StopServer
            Copy-Item -LiteralPath (Join-Path $backup 'rime.dll') -Destination $installedDll -Force
            Copy-Item -LiteralPath (Join-Path $backup 'local_ai_pinyin.schema.yaml') -Destination $installedSchema -Force
            InvokeLogged $deployer @('/deploy') 'rollback-schema' 120000
            StartServer
            Write-Warning "Previous engine and schema restored from $backup."
        } catch {
            Write-Warning "Automatic recovery could not finish: $_. Backup: $backup"
            try { StartServer } catch { Write-Warning "Service restart also failed: $_" }
        }
    }
    if ($newMock -and !$newMock.HasExited) { $newMock.Kill() }
    Write-Error -ErrorRecord $failure -ErrorAction Continue
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
