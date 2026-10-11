[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Stop', 'Restart')]
    [string]$Action,

    [string]$Root = 'C:\RainmeterDenon',

    [string]$LauncherPath = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Utilities\TelemetryProcessIdentity.ps1')

if ([string]::IsNullOrWhiteSpace($LauncherPath)) {
    $LauncherPath = Join-Path $Root 'LaunchTelemetryManager.vbs'
}

$scriptPaths = @(
    (Join-Path $Root 'TelemetryManager.ps1')
    (Join-Path $Root 'AvrWatchdog.ps1')
    (Join-Path $Root 'denon_status.ps1')
    (Join-Path $Root 'DecoderCollector.ps1')
    (Join-Path $Root 'Box1Collector.ps1')
    (Join-Path $Root 'NowPlaying\NowPlayingRouter.ps1')
    (Join-Path $Root 'NowPlaying\AppleMusicCollector.ps1')
    (Join-Path $Root 'NowPlaying\WiiM-NowPlaying-Bridge.ps1')
    (Join-Path $Root 'Utilities\RainmeterRefreshHotkey.ps1')
)

# Stop the manager first so it cannot replace a child while shutdown is in progress.
foreach ($scriptPath in $scriptPaths) {
    foreach ($process in @(Get-TelemetryScriptProcesses -ScriptPath $scriptPath)) {
        [void](Stop-TelemetryScriptProcess -Process $process)
    }
}

$deadline = (Get-Date).AddSeconds(5)
do {
    $remaining = @(
        foreach ($scriptPath in $scriptPaths) {
            Get-TelemetryScriptProcesses -ScriptPath $scriptPath
        }
    )

    if ($remaining.Count -eq 0) { break }
    Start-Sleep -Milliseconds 100
} while ((Get-Date) -lt $deadline)

$stopTimedOut = $remaining.Count -gt 0

$statePath = Join-Path $Root 'telemetry_manager_status.txt'
$stateLines = @(
    'Manager=Stopped'
    'ManagerPID='
    "Updated=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
)

try {
    [IO.File]::WriteAllLines($statePath, $stateLines, [Text.UTF8Encoding]::new($false))
}
catch {
    # Process shutdown must still complete if status publication is unavailable.
}

if ($stopTimedOut) {
    $remainingPIDs = ($remaining | Select-Object -ExpandProperty ProcessId) -join ','
    throw "Telemetry shutdown timed out; refusing to restart while exact telemetry PIDs remain: $remainingPIDs"
}

if ($Action -eq 'Restart') {
    if (-not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
        throw "Telemetry launcher not found: $LauncherPath"
    }

    Start-Process wscript.exe -ArgumentList @('"{0}"' -f $LauncherPath)
}
