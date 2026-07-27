param(
    [string]$DenonStatusPath = "C:\RainmeterDenon\denon_status.txt",
    [string]$NowPlayingPath = "C:\RainmeterDenon\NowPlaying\now_playing.txt",
    [string]$AppleCollectorPath = "C:\RainmeterDenon\NowPlaying\AppleMusicCollector.ps1",
    [string]$WiiMCollectorPath = "C:\RainmeterDenon\NowPlaying\WiiM-NowPlaying-Bridge.ps1",
    [int]$PollSeconds = 2
)

$ErrorActionPreference = "Continue"

$RouterDirectory = Split-Path -Parent $NowPlayingPath
$RouterHeartbeatPath = Join-Path $RouterDirectory "router_heartbeat.txt"
$RouterLogPath = Join-Path $RouterDirectory "router.log"
$RouterLogMaxBytes = 64KB
$RouterLogRetainedCharacters = 32KB
$RouterHeartbeatIntervalSeconds = 5

$script:ActiveMode = ""
$script:ActiveSource = ""
$script:ChildProcess = $null
$script:NextHeartbeat = Get-Date

function Write-RouterLog {
    param([Parameter(Mandatory)][string]$Message)

    try {
        New-Item -ItemType Directory -Path $RouterDirectory -Force | Out-Null

        if ((Test-Path -LiteralPath $RouterLogPath) -and
            (Get-Item -LiteralPath $RouterLogPath).Length -ge $RouterLogMaxBytes) {

            $existing = [IO.File]::ReadAllText($RouterLogPath)
            if ($existing.Length -gt $RouterLogRetainedCharacters) {
                $existing = $existing.Substring($existing.Length - $RouterLogRetainedCharacters)
            }
            [IO.File]::WriteAllText($RouterLogPath, $existing, [Text.UTF8Encoding]::new($false))
        }

        Add-Content -LiteralPath $RouterLogPath `
            -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message) `
            -Encoding UTF8
    }
    catch {}
}

function Write-RouterHeartbeat {
    try {
        Set-Content -LiteralPath $RouterHeartbeatPath -Value (Get-Date -Format "o") -Encoding ASCII
    }
    catch {}
}

function Get-DenonState {
    $state = @{
        Source = ""
        Mode = ""
        InputSignal = ""
    }

    if (-not (Test-Path -LiteralPath $DenonStatusPath)) {
        return $state
    }

    try {
        foreach ($line in Get-Content -LiteralPath $DenonStatusPath -ErrorAction Stop) {
            if ($line -match '^(Source|Mode|InputSignal)=(.*)$') {
                $state[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }
    catch {
        Write-Warning "Could not read Denon status: $($_.Exception.Message)"
    }

    return $state
}

function Get-CollectorProcesses {
    param([Parameter(Mandatory)][string]$ScriptPath)

    $leaf = [IO.Path]::GetFileName($ScriptPath)
    return Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            ($_.CommandLine.IndexOf($leaf, [StringComparison]::OrdinalIgnoreCase) -ge 0)
        }
}

function Stop-MatchingCollector {
    param([Parameter(Mandatory)][string]$ScriptPath)

    foreach ($process in @(Get-CollectorProcesses -ScriptPath $ScriptPath)) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
            Write-Host "$(Get-Date -Format HH:mm:ss) Stopped PID $($process.ProcessId): $([IO.Path]::GetFileName($ScriptPath))"
            Write-RouterLog "Stopped PID $($process.ProcessId): $([IO.Path]::GetFileName($ScriptPath))."
        }
        catch {
            Write-Warning "Could not stop PID $($process.ProcessId): $($_.Exception.Message)"
        }
    }
}

function Stop-CurrentCollector {
    if ($null -ne $script:ChildProcess) {
        try {
            if (-not $script:ChildProcess.HasExited) {
                Stop-Process -Id $script:ChildProcess.Id -Force -ErrorAction Stop
                Write-Host "$(Get-Date -Format HH:mm:ss) Stopped $($script:ActiveMode) collector."
                Write-RouterLog "Stopped $($script:ActiveMode) collector PID $($script:ChildProcess.Id)."
            }
        }
        catch {
            Write-Warning "Could not stop active collector: $($_.Exception.Message)"
        }
    }

    # Also clean up any stray copy that was started outside this router.
    Stop-MatchingCollector -ScriptPath $AppleCollectorPath
    Stop-MatchingCollector -ScriptPath $WiiMCollectorPath

    $script:ChildProcess = $null
    $script:ActiveMode = ""
    $script:ActiveSource = ""
}

function Start-Collector {
    param(
        [Parameter(Mandatory)][ValidateSet("Apple","WiiM")][string]$Mode,
        [Parameter(Mandatory)][string]$Source
    )

    $path = if ($Mode -eq "Apple") { $AppleCollectorPath } else { $WiiMCollectorPath }

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warning "$Mode collector not found: $path"
        return
    }

    try {
        $script:ChildProcess = Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", ('"{0}"' -f $path)
            ) `
            -WindowStyle Hidden `
            -PassThru

        $script:ActiveMode = $Mode
        $script:ActiveSource = $Source
        Write-Host "$(Get-Date -Format HH:mm:ss) Started $Mode collector (PID $($script:ChildProcess.Id))."
        Write-RouterLog "Started $Mode collector PID $($script:ChildProcess.Id) for Source=$Source."
    }
    catch {
        Write-Warning "Could not start $Mode collector: $($_.Exception.Message)"
        Write-RouterLog "Failed to start $Mode collector: $($_.Exception.Message)"
        $script:ChildProcess = $null
        $script:ActiveMode = ""
    }
}

function Write-InactiveNowPlaying {
    $directory = Split-Path -Parent $NowPlayingPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $content = @(
        "Active=0"
        "Source="
        "Title="
        "Artist="
        "Album="
        "PositionSeconds=0"
        "DurationSeconds=0"
        "Position="
        "Duration="
        "Progress=0"
        "ArtworkAvailable=0"
        "Artwork="
        ""
    ) -join "`r`n"

    $tempPath = "$NowPlayingPath.tmp"
    [IO.File]::WriteAllText($tempPath, $content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $NowPlayingPath -Force
}

function Set-Mode {
    param(
        [Parameter(Mandatory)][ValidateSet("Apple","WiiM","None")][string]$Mode,
        [Parameter(Mandatory)][string]$Source
    )

    $collectorHealthy =
        ($null -ne $script:ChildProcess) -and
        (-not $script:ChildProcess.HasExited)

    if (($null -ne $script:ChildProcess) -and
        $script:ChildProcess.HasExited -and
        $script:ActiveMode -in @("Apple", "WiiM")) {

        Write-RouterLog "Unexpected $($script:ActiveMode) collector exit for Source=$Source; PID $($script:ChildProcess.Id), exit code $($script:ChildProcess.ExitCode)."
    }

    if (($Mode -eq $script:ActiveMode) -and
        ($Source -eq $script:ActiveSource) -and
        (($Mode -eq "None") -or $collectorHealthy)) {

        return
    }

    if ($Mode -eq $script:ActiveMode -and $Source -eq $script:ActiveSource) {
        Write-RouterLog "Restart decision: $Mode collector is not running for Source=$Source."
    }
    elseif ($Mode -eq $script:ActiveMode) {
        Write-RouterLog "Source change: $($script:ActiveSource) -> $Source; collector remains $Mode."
    }
    else {
        $previousMode = if ([string]::IsNullOrWhiteSpace($script:ActiveMode)) { "None" } else { $script:ActiveMode }
        Write-RouterLog "Collector change: $previousMode -> $Mode for Source=$Source."
    }

    Stop-CurrentCollector

    switch ($Mode) {
        "Apple" { Start-Collector -Mode "Apple" -Source $Source }
        "WiiM"  { Start-Collector -Mode "WiiM" -Source $Source }
        "None"  {
            Write-InactiveNowPlaying
            $script:ActiveMode = "None"
            $script:ActiveSource = $Source
            Write-Host "$(Get-Date -Format HH:mm:ss) Now Playing hidden for Source=$Source."
            Write-RouterLog "Now Playing hidden for Source=$Source."
        }
    }
}

New-Item -ItemType Directory -Path $RouterDirectory -Force | Out-Null
Write-RouterLog "Now Playing Router started. PID=$PID."
Write-RouterHeartbeat
$script:NextHeartbeat = (Get-Date).AddSeconds($RouterHeartbeatIntervalSeconds)

# Take ownership of now_playing.txt.
Stop-MatchingCollector -ScriptPath $AppleCollectorPath
Stop-MatchingCollector -ScriptPath $WiiMCollectorPath

Write-Host "Now Playing Router v2 started."
Write-Host "Source=HTPC -> Apple Music"
Write-Host "Source=LYR+ -> WiiM"
Write-Host "Other sources -> hide Now Playing"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

$lastSignature = ""

try {
    while ($true) {
        if ((Get-Date) -ge $script:NextHeartbeat) {
            Write-RouterHeartbeat
            $script:NextHeartbeat = (Get-Date).AddSeconds($RouterHeartbeatIntervalSeconds)
        }

        $state = Get-DenonState
        $source = ([string]$state.Source).Trim().ToUpperInvariant()

        if ($source -eq "HTPC") {
            $desiredMode = "Apple"
        }
        elseif ($source -eq "LYR+") {
            $desiredMode = "WiiM"
        }
        else {
            $desiredMode = "None"
        }

        $signature = "$source|$desiredMode"
        if ($signature -ne $lastSignature) {
            Write-Host "$(Get-Date -Format HH:mm:ss) Source='$source' -> $desiredMode"
            $lastSignature = $signature
        }

        Set-Mode -Mode $desiredMode -Source $source
        Start-Sleep -Seconds $PollSeconds
    }
}
finally {
    Write-RouterLog "Now Playing Router shutting down. PID=$PID."
    Stop-CurrentCollector
    Write-RouterLog "Now Playing Router stopped. PID=$PID."
}
