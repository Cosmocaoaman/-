# Keep logs readable while long setup/build commands are still running.
function Invoke-LoggedProcess {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$WorkingDirectory,
          [string]$LogDirectory, [string]$Label, [int]$TimeoutMilliseconds = 0)
    New-Item -ItemType Directory -Force $LogDirectory | Out-Null
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    # Weasel requires the exact /q or /deploy command line, without trailing spaces.
    $info.Arguments = [string]::Join(' ', $ArgumentList).Trim()
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $streams = @()
    $started = $false
    try {
        $started = $proc.Start()
        foreach ($entry in @(@('out', $proc.StandardOutput), @('err', $proc.StandardError))) {
            $writer = New-Object IO.StreamWriter((Join-Path $LogDirectory "$Label.$($entry[0]).log"), $false, [Text.Encoding]::UTF8)
            $writer.AutoFlush = $true
            $streams += @{ Reader=$entry[1]; Writer=$writer; Pending=$entry[1].ReadLineAsync(); Done=$false }
        }
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $nextProgress = 15
        while (!$proc.HasExited -or @($streams | Where-Object { !$_.Done }).Count) {
            foreach ($stream in $streams) {
                if (!$stream.Done -and $stream.Pending.IsCompleted) {
                    $line = $stream.Pending.GetAwaiter().GetResult()
                    if ($null -eq $line) { $stream.Done = $true }
                    else {
                        $stream.Writer.WriteLine($line)
                        Write-Host $line
                        $stream.Pending = $stream.Reader.ReadLineAsync()
                    }
                }
            }
            if ($TimeoutMilliseconds -gt 0 -and $timer.ElapsedMilliseconds -gt $TimeoutMilliseconds -and !$proc.HasExited) {
                $proc.Kill()
                $proc.WaitForExit()
                throw "$Label timed out. See $LogDirectory"
            }
            if ($timer.Elapsed.TotalSeconds -ge $nextProgress) {
                Write-Host "[$Label] Still running ($([int]$timer.Elapsed.TotalSeconds)s). Logs: $LogDirectory"
                $nextProgress += 15
            }
            # Drain buffered output without a delay; wait only for pending IO.
            if (!@($streams | Where-Object { !$_.Done -and $_.Pending.IsCompleted }).Count) { Start-Sleep -Milliseconds 50 }
        }
        $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) { throw "$Label failed (exit $($proc.ExitCode)). See $LogDirectory" }
    } finally {
        if ($started -and !$proc.HasExited) { $proc.Kill(); $proc.WaitForExit() }
        foreach ($stream in $streams) { $stream.Writer.Dispose() }
        $proc.Dispose()
    }
}
