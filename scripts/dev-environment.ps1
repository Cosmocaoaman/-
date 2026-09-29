# Resolve a working interpreter, including Windows installations exposed only by py.
function Resolve-DevPython {
    param([string]$Root, [string]$Python = '', [switch]$Base)
    $candidates = @()
    if ($Python) {
        $candidates += (Get-Command $Python -ErrorAction Stop).Source
    } else {
        if (!$Base) { $candidates += Join-Path $Root '.venv\Scripts\python.exe' }
        $launcher = Get-Command py -ErrorAction SilentlyContinue
        if ($launcher) {
            try {
                $discovered = & $launcher.Source -3 -c 'import sys; print(sys.executable)' 2>$null
                if ($LASTEXITCODE -eq 0) { $candidates += $discovered }
            } catch { }
        }
        $command = Get-Command python -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (!(Test-Path -LiteralPath $candidate -PathType Leaf) -or $candidate -match '\\WindowsApps\\') { continue }
        try {
            $expression = if ($Base) { 'import sys; assert sys.version_info >= (3,11); print(sys._base_executable)' } else { 'import sys; assert sys.version_info >= (3,11); print(sys.executable)' }
            $resolved = & $candidate -c $expression 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $resolved -PathType Leaf)) { return $resolved }
        } catch { }
    }
    throw 'No working Python 3.11+ found. Install Python with the py launcher, or pass -Python C:\path\to\python.exe.'
}

# Pure selection logic is separate from machine discovery so it can be tested.
function Select-WeaselInstallation {
    param([string]$ExplicitPath, [string[]]$RunningPaths = @(), [string[]]$CandidatePaths = @())
    if ($ExplicitPath) {
        $path = (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
        if (!(Test-Path -LiteralPath (Join-Path $path 'WeaselServer.exe') -PathType Leaf)) { throw 'Invalid -InstallDir: WeaselServer.exe is missing.' }
        return $path
    }
    $running = @($RunningPaths | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Sort-Object -Unique)
    if ($running.Count -gt 1) { throw 'Multiple Weasel installations are running. Specify -InstallDir and close the other installation.' }
    if ($running.Count -eq 1) { return Select-WeaselInstallation -ExplicitPath $running[0] }
    $candidates = @($CandidatePaths | Where-Object { $_ } | ForEach-Object {
        $path = [Environment]::ExpandEnvironmentVariables($_)
        if (Test-Path -LiteralPath (Join-Path $path 'WeaselServer.exe') -PathType Leaf) { (Resolve-Path -LiteralPath $path).Path }
    } | Sort-Object -Unique)
    if ($candidates.Count -gt 1) { throw 'Multiple installed copies found. Specify -InstallDir explicitly.' }
    if ($candidates.Count -eq 0) { throw 'No installed Weasel found. Install official Weasel first, specify -InstallDir, or use -BuildOnly.' }
    return $candidates[0]
}
function Find-WeaselInstallation {
    param([string]$ExplicitPath)
    $running = @(Get-CimInstance Win32_Process -Filter "Name = 'WeaselServer.exe'")
    if (@($running | Where-Object { !$_.ExecutablePath }).Count) { throw 'Cannot inspect a running Weasel process. Use the same user/appropriate permissions.' }
    $paths = @($running | ForEach-Object { Split-Path $_.ExecutablePath -Parent })
    $candidates = @()
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryHive]::CurrentUser)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)) {
            $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
            $key = $null
            try {
                $key = $registry.OpenSubKey('Software\Rime\Weasel')
                if ($key) { $candidates += $key.GetValue('InstallDir') }
            } finally { if ($key) { $key.Dispose() }; $registry.Dispose() }
        }
    }
    $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\RimeAI')
    Select-WeaselInstallation -ExplicitPath $ExplicitPath -RunningPaths $paths -CandidatePaths $candidates
}
function Assert-DevPrerequisites {
    param([string]$Root, [string]$Python)
    if ($Root -match '[^\x00-\x7F]|\s') { throw 'Use an ASCII checkout path without spaces, e.g. C:\dev\rime-ai (upstream build limitation).' }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (!(Test-Path $vswhere)) { throw 'Install Visual Studio 2022 C++ Build Tools and Windows SDK first.' }
    $vs = & $vswhere -latest -version '[17.0,18.0)' -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$vs) { throw 'Visual Studio 2022 x86/x64 C++ tools were not found.' }
    foreach ($relative in @('librime\deps\boost\boost\version.hpp','ai\rime-data\luna_pinyin.dict.yaml','ai\rime-data\essay.txt','ai\rime-data\opencc\t2s.json')) {
        if (!(Test-Path (Join-Path $Root $relative))) { throw "Missing $relative. Run .\dev.cmd -Setup (or -Setup -BuildOnly)." }
    }
    foreach ($tool in @('cmake','ninja')) {
        $localPaths = @((Join-Path $Root ".venv\Scripts\$tool.exe"), (Join-Path $Root ".build-tools\python-tools\bin\$tool.exe"), (Join-Path $Root ".build-tools\cmake4\cmake\data\bin\$tool.exe"))
        if (!@($localPaths | Where-Object { Test-Path $_ }).Count -and !(Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Missing $tool. Run .\dev.cmd -Setup." }
    }
    & $Python -c 'import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)'
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.11+ is required; specify -Python with its full path.' }
}
