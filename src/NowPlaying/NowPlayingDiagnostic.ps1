$script:NowPlayingDiagnosticPath = 'C:\RainmeterDenon\Logs\NowPlayingDiagnostic.log'
$script:NowPlayingDiagnosticMaxBytes = 3MB
$script:NowPlayingDiagnosticRetainedFiles = 4

function Write-NowPlayingDiagnostic {
    param(
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Event,
        [hashtable]$Fields = @{}
    )

    # Diagnostics must never delay or stop a collector.
    $mutex = $null
    $lockTaken = $false
    try {
        $logDirectory = Split-Path -Parent $script:NowPlayingDiagnosticPath
        New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null

        $mutex = [Threading.Mutex]::new($false, 'Local\RainmeterDenonNowPlayingDiagnostic')
        $lockTaken = $mutex.WaitOne(100)
        if (-not $lockTaken) { return }

        if ((Test-Path -LiteralPath $script:NowPlayingDiagnosticPath) -and
            (Get-Item -LiteralPath $script:NowPlayingDiagnosticPath).Length -ge $script:NowPlayingDiagnosticMaxBytes) {

            for ($index = $script:NowPlayingDiagnosticRetainedFiles; $index -ge 1; $index--) {
                $source = if ($index -eq 1) {
                    $script:NowPlayingDiagnosticPath
                }
                else {
                    '{0}.{1}' -f $script:NowPlayingDiagnosticPath, ($index - 1)
                }
                $destination = '{0}.{1}' -f $script:NowPlayingDiagnosticPath, $index
                if (Test-Path -LiteralPath $source) {
                    Move-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
                }
            }
        }

        $record = [ordered]@{
            timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'
            component = $Component
            event = $Event
            pid = $PID
        }
        foreach ($key in $Fields.Keys) { $record[$key] = $Fields[$key] }
        $line = $record | ConvertTo-Json -Compress -Depth 4
        [IO.File]::AppendAllText(
            $script:NowPlayingDiagnosticPath,
            $line + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
        )
    }
    catch {
        # Logging is deliberately best-effort and cannot affect telemetry.
    }
    finally {
        if ($lockTaken -and $null -ne $mutex) {
            try { $mutex.ReleaseMutex() } catch {}
        }
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
}
