param(
    [string]$DenonStatusPath = "C:\RainmeterDenon\denon_status.txt",
    [string]$NowPlayingPath = "C:\RainmeterDenon\NowPlaying\now_playing.txt",
    [string]$AppleCollectorPath = "C:\RainmeterDenon\NowPlaying\AppleMusicCollector.ps1",
    [string]$WiiMCollectorPath = "C:\RainmeterDenon\NowPlaying\WiiM-NowPlaying-Bridge.ps1",
    [int]$PollSeconds = 2
)

$ErrorActionPreference = "Continue"

# Your present Quick Select map:
#   1 = HTPC Dolby
#   2 = HTPC Multi
#   3 = LYR+ Stereo
#   4 = LYR+ Multi
$AppleQuickSelects = @("1", "2")
$WiiMQuickSelects  = @("3", "4")

$script:ActiveMode = ""
$script:ChildProcess = $null

function Get-DenonState {
    $state = @{
        Source = ""
        QuickSelect = ""
        QuickSelectName = ""
        Mode = ""
        InputSignal = ""
    }

    if (-not (Test-Path -LiteralPath $DenonStatusPath)) {
        return $state
    }

    try {
        foreach ($line in Get-Content -LiteralPath $DenonStatusPath -ErrorAction Stop) {
            if ($line -match '^(Source|QuickSelect|QuickSelectName|Mode|InputSignal)=(.*)$') {
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
}

function Start-Collector {
    param([Parameter(Mandatory)][ValidateSet("Apple","WiiM")][string]$Mode)

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
        Write-Host "$(Get-Date -Format HH:mm:ss) Started $Mode collector (PID $($script:ChildProcess.Id))."
    }
    catch {
        Write-Warning "Could not start $Mode collector: $($_.Exception.Message)"
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
        [hashtable]$State
    )

    $collectorHealthy =
        ($null -ne $script:ChildProcess) -and
        (-not $script:ChildProcess.HasExited)

    if (($Mode -eq $script:ActiveMode) -and (($Mode -eq "None") -or $collectorHealthy)) {
        return
    }

    Stop-CurrentCollector

    switch ($Mode) {
        "Apple" { Start-Collector -Mode "Apple" }
        "WiiM"  { Start-Collector -Mode "WiiM" }
        "None"  {
            Write-InactiveNowPlaying
            $script:ActiveMode = "None"
            Write-Host "$(Get-Date -Format HH:mm:ss) Now Playing hidden (Quick Select $($State.QuickSelect): $($State.QuickSelectName))."
        }
    }
}

# Take ownership of now_playing.txt.
Stop-MatchingCollector -ScriptPath $AppleCollectorPath
Stop-MatchingCollector -ScriptPath $WiiMCollectorPath

Write-Host "Now Playing Router v2 started."
Write-Host "Quick Selects 1-2 -> Apple Music"
Write-Host "Quick Selects 3-4 -> WiiM"
Write-Host "Anything else      -> hide Now Playing"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

$lastSignature = ""

try {
    while ($true) {
        $state = Get-DenonState
        $quickSelect = [string]$state.QuickSelect

        if ($quickSelect -in $AppleQuickSelects) {
            $desiredMode = "Apple"
        }
        elseif ($quickSelect -in $WiiMQuickSelects) {
            $desiredMode = "WiiM"
        }
        else {
            $desiredMode = "None"
        }

        $signature = "$($state.Source)|$($state.QuickSelect)|$($state.QuickSelectName)|$desiredMode"
        if ($signature -ne $lastSignature) {
            Write-Host "$(Get-Date -Format HH:mm:ss) Source='$($state.Source)' QuickSelect='$($state.QuickSelect)' Name='$($state.QuickSelectName)' -> $desiredMode"
            $lastSignature = $signature
        }

        Set-Mode -Mode $desiredMode -State $state
        Start-Sleep -Seconds $PollSeconds
    }
}
finally {
    Stop-CurrentCollector
}
