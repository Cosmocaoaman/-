$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $PSScriptRoot 'runtime\weasel'
$destination = Join-Path $PSScriptRoot 'dist\weasel-ai-dev'
$engine = Join-Path $root 'librime\dist-x86\lib\rime.dll'
if (!(Test-Path $engine) -or !(Test-Path (Join-Path $source 'WeaselServer.exe'))) {
    throw 'Build the x86 AI engine and prepare the official Weasel frontend first.'
}
function Machine($file) {
    $bytes = [IO.File]::ReadAllBytes($file)
    $offset = [BitConverter]::ToInt32($bytes, 0x3c)
    return [BitConverter]::ToUInt16($bytes, $offset + 4)
}
if ((Machine $engine) -ne 0x14c -or (Machine (Join-Path $source 'WeaselServer.exe')) -ne 0x14c) {
    throw 'Engine/server architecture mismatch: this package requires x86.'
}
New-Item -ItemType Directory -Force $destination | Out-Null
Get-ChildItem $source | Where-Object Name -NotIn @('$PLUGINSDIR', 'uninstall.exe', 'rime.dll') |
    Copy-Item -Destination $destination -Recurse -Force
Copy-Item $engine (Join-Path $destination 'rime.dll') -Force
foreach ($name in @('default.yaml', 'local_ai_pinyin.schema.yaml', 'luna_pinyin.dict.yaml', 'essay.txt', 'opencc')) {
    Copy-Item (Join-Path $PSScriptRoot "rime-data\$name") (Join-Path $destination 'data') -Recurse -Force
}
Copy-Item (Join-Path $PSScriptRoot 'README.zh-CN.md') (Join-Path $destination 'AI-README.zh-CN.md') -Force
Copy-Item (Join-Path $root 'README.md') (Join-Path $destination 'SOURCE-README.md') -Force
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $destination 'LOCAL-AI-LICENSE.txt') -Force
Copy-Item (Join-Path $root 'librime\LICENSE') (Join-Path $destination 'LIBRIME-LICENSE.txt') -Force
Copy-Item (Join-Path $root 'THIRD_PARTY_NOTICES.md') $destination -Force
$manifest = [ordered]@{
    builtAt = (Get-Date).ToString('o')
    frontend = 'Official Weasel 0.17.4.0 prebuilt, x86 server'
    engine = 'Locally compiled librime 1.17.0 + local_ai module, x86 Release'
    engineSha256 = (Get-FileHash $engine -Algorithm SHA256).Hash
    endpoint = 'http://127.0.0.1:18080/v1/chat/completions'
    futureModelAlias = 'qwen3.5-0.8b'
    modelIncluded = $false
    systemRegistered = $false
}
$manifest | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $destination 'ai-build-manifest.json')
Write-Host "Prepared: $destination"
