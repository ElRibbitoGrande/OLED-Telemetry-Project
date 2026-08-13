[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'OLED-Telemetry\NowPlayingCaptures'),
    [int]$TailLines = 500
)

$ErrorActionPreference = 'Continue'
$runtimeRoot = 'C:\RainmeterDenon'
$nowPlayingRoot = Join-Path $runtimeRoot 'NowPlaying'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$capturePath = Join-Path $OutputRoot $stamp
New-Item -ItemType Directory -Path $capturePath -Force -ErrorAction Stop | Out-Null

$stateFiles = @(
    (Join-Path $nowPlayingRoot 'now_playing.txt'),
    (Join-Path $nowPlayingRoot 'router_heartbeat.txt'),
    (Join-Path $runtimeRoot 'denon_status.txt'),
    (Join-Path $runtimeRoot 'telemetry_manager_status.txt')
)

$logFiles = @(
    (Join-Path $runtimeRoot 'Logs\NowPlayingDiagnostic.log'),
    (Join-Path $runtimeRoot 'Logs\NowPlayingDiagnostic.log.1'),
    (Join-Path $runtimeRoot 'Logs\NowPlayingRainmeter.log'),
    (Join-Path $runtimeRoot 'Logs\NowPlayingRainmeter.log.1'),
    (Join-Path $nowPlayingRoot 'router.log'),
    (Join-Path $nowPlayingRoot 'apple_music_collector.log'),
    (Join-Path $runtimeRoot 'telemetry_manager.log')
)

$manifest = [Collections.Generic.List[object]]::new()
foreach ($path in $stateFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $item = Get-Item -LiteralPath $path
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    $destination = Join-Path $capturePath $item.Name
    Copy-Item -LiteralPath $path -Destination $destination
    $manifest.Add([pscustomobject]@{
        Path = $path
        Length = $item.Length
        CreationTime = $item.CreationTime.ToString('o')
        LastWriteTime = $item.LastWriteTime.ToString('o')
        SHA256 = $hash.Hash
    })
}

foreach ($path in $logFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $item = Get-Item -LiteralPath $path
    $destination = Join-Path $capturePath ($item.Name + '.tail.txt')
    Get-Content -LiteralPath $path -Tail $TailLines | Set-Content -LiteralPath $destination -Encoding UTF8
}

$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $capturePath 'file_manifest.json') -Encoding UTF8

try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
        Where-Object { $_.CommandLine -match 'TelemetryManager|NowPlayingRouter|AppleMusicCollector|WiiM-NowPlaying' } |
        Select-Object ProcessId, CreationDate, CommandLine |
        Format-List |
        Out-File -LiteralPath (Join-Path $capturePath 'now_playing_processes.txt') -Encoding UTF8
}
catch {
    "Process inventory unavailable: $($_.Exception.Message)" |
        Set-Content -LiteralPath (Join-Path $capturePath 'now_playing_processes.txt') -Encoding UTF8
}

@(
    "Captured=$(Get-Date -Format 'o')"
    "Computer=$env:COMPUTERNAME"
    "User=$env:USERNAME"
    "RuntimeRoot=$runtimeRoot"
    "Note=This capture did not restart telemetry or refresh Rainmeter."
) | Set-Content -LiteralPath (Join-Path $capturePath 'capture_info.txt') -Encoding UTF8

Write-Output $capturePath
