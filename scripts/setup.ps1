param([string]$Python = '', [string]$SevenZip = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ($root -match '[^\x00-\x7F]|\s') { throw 'Extract or clone to an ASCII path without spaces, e.g. C:\dev\rime-ai.' }
. (Join-Path $PSScriptRoot 'dev-environment.ps1')
$Python = Resolve-DevPython -Root $root -Python $Python -Base
if (!$SevenZip) {
    $command = Get-Command 7z -ErrorAction SilentlyContinue
    if ($command) { $SevenZip = $command.Source }
    elseif (Test-Path "$env:ProgramFiles\7-Zip\7z.exe") { $SevenZip = "$env:ProgramFiles\7-Zip\7z.exe" }
    else { throw 'Install 7-Zip or pass -SevenZip C:\path\to\7z.exe.' }
}
$downloads = Join-Path $root '.downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null
function Download-Checked($url, $name, $sha) {
    $file = Join-Path $downloads $name
    if (!(Test-Path $file)) {
        Write-Host "Downloading $name..."
        $partial = "$file.partial"
        $previousProgress = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing $url -OutFile $partial
            if ((Get-FileHash $partial -Algorithm SHA256).Hash -ne $sha) { throw "Checksum mismatch: $partial" }
            Move-Item -LiteralPath $partial -Destination $file
        } finally { $ProgressPreference = $previousProgress }
    }
    if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $sha) {
        throw "Checksum mismatch: $file. Remove this download and rerun."
    }
    return $file
}
Write-Host "Preparing Python environment with $Python..."
& $Python -m venv (Join-Path $root '.venv')
if ($LASTEXITCODE) { throw 'Python 3.11+ with venv is required.' }
$venvPython = Join-Path $root '.venv\Scripts\python.exe'
& $venvPython -m pip --disable-pip-version-check install --force-reinstall 'cmake==4.1.3' 'ninja==1.13.0'
if ($LASTEXITCODE) { throw 'Failed to install CMake/Ninja.' }
if (!(Test-Path (Join-Path $root 'librime\deps\boost\boost\version.hpp'))) {
    $boost = Download-Checked 'https://archives.boost.io/release/1.92.0/source/boost_1_92_0.7z' 'boost_1_92_0.7z' '57f2ded2390068a44d88748425067e01a8c285257a4d9611d04ade9d8ec68615'
    Write-Host 'Extracting Boost (this can take several minutes)...'
    & $SevenZip x $boost "-o$downloads" -y | Out-Null
    if ($LASTEXITCODE) { throw 'Boost extraction failed.' }
    $boostTarget = Join-Path $root 'librime\deps\boost'
    if (Test-Path -LiteralPath $boostTarget) { throw "Incomplete Boost directory: $boostTarget. Move it aside and rerun setup." }
    $boostSource = (Resolve-Path -LiteralPath (Join-Path $downloads 'boost_1_92_0')).Path
    if ($boostSource -ne (Join-Path $downloads 'boost_1_92_0')) { throw 'Unexpected Boost extraction path.' }
    Move-Item -LiteralPath $boostSource -Destination $boostTarget
}
$frontend = Download-Checked 'https://github.com/rime/weasel/releases/download/0.17.4/weasel-0.17.4.0-installer.exe' 'weasel-0.17.4.0-installer.exe' 'cf509534a8f5f8af9c98ed7cbb8f135439f145a8cbe7e50ede42bb5b5ab45c29'
$runtime = Join-Path $root 'ai\runtime\weasel'
Write-Host 'Extracting Weasel runtime and dictionaries...'
& $SevenZip x $frontend "-o$runtime" -y | Out-Null
if ($LASTEXITCODE) { throw 'Weasel extraction failed.' }
$data = Join-Path $root 'ai\rime-data'
foreach ($name in @('essay.txt', 'luna_pinyin.dict.yaml', 'opencc')) {
    $source = Join-Path $runtime "data\$name"
    if (Test-Path -LiteralPath $source -PathType Container) {
        $destination = Join-Path $data $name
        New-Item -ItemType Directory -Force $destination | Out-Null
        Get-ChildItem -LiteralPath $source | Copy-Item -Destination $destination -Recurse -Force
    } else { Copy-Item -LiteralPath $source -Destination (Join-Path $data $name) -Force }
}
New-Item -ItemType Directory -Force (Join-Path $root 'ai\logs') | Out-Null
Write-Host 'Ready. Run .\dev.cmd -BuildOnly. No system input method was installed.'
