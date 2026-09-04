[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\RainmeterDenon',
    [string]$OutputRoot = 'C:\RainmeterDenon\Diagnostics\Artwork',
    [int]$TailLines = 500
)

$ErrorActionPreference = 'Continue'
$nowPlayingRoot = Join-Path $RuntimeRoot 'NowPlaying'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$capturePath = Join-Path $OutputRoot $stamp
New-Item -ItemType Directory -Path $capturePath -Force -ErrorAction Stop | Out-Null

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$Path)

    $stream = $null
    $algorithm = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $algorithm = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        if ($algorithm) { $algorithm.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

$diagnosticHelper = Join-Path $nowPlayingRoot 'NowPlayingDiagnostic.ps1'
if (Test-Path -LiteralPath $diagnosticHelper -PathType Leaf) {
    try {
        . $diagnosticHelper
        Write-NowPlayingDiagnostic -Component 'ArtworkDiagnosticHotkey' -Event 'ARTWORK_DIAGNOSTIC_CAPTURE' -Fields @{
            capturePath = $capturePath; hotkey = 'Ctrl+Alt+F10'; observationOnly = $true
        }
    }
    catch {}
}

$stateFiles = @(
    (Join-Path $nowPlayingRoot 'now_playing.txt'),
    (Join-Path $nowPlayingRoot 'rainmeter_artwork_state.txt'),
    (Join-Path $nowPlayingRoot 'router_heartbeat.txt'),
    (Join-Path $RuntimeRoot 'denon_status.txt'),
    (Join-Path $RuntimeRoot 'telemetry_manager_status.txt')
)
$artworkFiles = @(
    (Join-Path $nowPlayingRoot 'artwork_a.jpg'),
    (Join-Path $nowPlayingRoot 'artwork_b.jpg'),
    (Join-Path $nowPlayingRoot 'wiim_artwork_a.jpg'),
    (Join-Path $nowPlayingRoot 'wiim_artwork_b.jpg'),
    (Join-Path $nowPlayingRoot 'wiim_artwork.jpg')
)
$logFiles = @(
    (Join-Path $RuntimeRoot 'Logs\NowPlayingDiagnostic.log'),
    (Join-Path $RuntimeRoot 'Logs\NowPlayingDiagnostic.log.1'),
    (Join-Path $RuntimeRoot 'Logs\NowPlayingRainmeter.log'),
    (Join-Path $RuntimeRoot 'Logs\NowPlayingRainmeter.log.1'),
    (Join-Path $RuntimeRoot 'Logs\RainmeterRefreshHotkey.log'),
    (Join-Path $nowPlayingRoot 'router.log'),
    (Join-Path $nowPlayingRoot 'apple_music_collector.log'),
    (Join-Path $RuntimeRoot 'telemetry_manager.log')
)

$manifest = [Collections.Generic.List[object]]::new()
foreach ($path in @($stateFiles + $artworkFiles)) {
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $row = [ordered]@{ Path = $path; Exists = $exists; Length = $null; LastWriteTime = $null; SHA256 = $null; Error = $null }
    if ($exists) {
        try {
            $item = Get-Item -LiteralPath $path -ErrorAction Stop
            $row.Length = $item.Length
            $row.LastWriteTime = $item.LastWriteTime.ToString('o')
            $row.SHA256 = Get-Sha256Hex -Path $path
            Copy-Item -LiteralPath $path -Destination (Join-Path $capturePath $item.Name) -ErrorAction Stop
        }
        catch { $row.Error = $_.Exception.Message }
    }
    $manifest.Add([pscustomobject]$row)
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $capturePath 'file_manifest.json') -Encoding UTF8

foreach ($path in $logFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    try {
        $item = Get-Item -LiteralPath $path
        Get-Content -LiteralPath $path -Tail $TailLines -ErrorAction Stop |
            Set-Content -LiteralPath (Join-Path $capturePath ($item.Name + '.tail.txt')) -Encoding UTF8
    }
    catch {}
}

$processRows = [Collections.Generic.List[object]]::new()
try {
    Get-CimInstance Win32_Process -ErrorAction Stop |
        Where-Object {
            $_.Name -eq 'Rainmeter.exe' -or
            $_.CommandLine -match 'TelemetryManager|NowPlayingRouter|AppleMusicCollector|WiiM-NowPlaying|RainmeterRefreshHotkey'
        } |
        ForEach-Object {
            $processRows.Add([pscustomobject]@{
                ProcessId = $_.ProcessId; ParentProcessId = $_.ParentProcessId
                Name = $_.Name; CreationDate = $_.CreationDate; CommandLine = $_.CommandLine
            })
        }
}
catch {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -in @('Rainmeter', 'powershell') } |
        ForEach-Object {
            $processRows.Add([pscustomobject]@{
                ProcessId = $_.Id; ParentProcessId = $null; Name = $_.ProcessName
                CreationDate = $(try { $_.StartTime.ToString('o') } catch { $null })
                CommandLine = $null
            })
        }
}
$processRows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $capturePath 'processes.json') -Encoding UTF8

$stateValues = [ordered]@{}
$statePath = Join-Path $nowPlayingRoot 'now_playing.txt'
for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        foreach ($line in Get-Content -LiteralPath $statePath -ErrorAction Stop) {
            if ($line -match '^([^=]+)=(.*)$') { $stateValues[$Matches[1]] = $Matches[2] }
        }
        if ($stateValues.Contains('Active') -and $stateValues.Contains('ArtworkAvailable')) { break }
    }
    catch { Start-Sleep -Milliseconds (25 * $attempt) }
}
$advertisedArtwork = [string]$stateValues.Artwork
$advertisedItem = if (-not [string]::IsNullOrWhiteSpace($advertisedArtwork) -and
    (Test-Path -LiteralPath $advertisedArtwork -PathType Leaf)) { Get-Item -LiteralPath $advertisedArtwork } else { $null }

$rainmeterValues = [ordered]@{}
$rainmeterStatePath = Join-Path $nowPlayingRoot 'rainmeter_artwork_state.txt'
if (Test-Path -LiteralPath $rainmeterStatePath -PathType Leaf) {
    try {
        foreach ($line in Get-Content -LiteralPath $rainmeterStatePath -ErrorAction Stop) {
            if ($line -match '^([^=]+)=(.*)$') { $rainmeterValues[$Matches[1]] = $Matches[2] }
        }
    }
    catch {}
}

[pscustomobject]@{
    Marker = 'ARTWORK_DIAGNOSTIC_CAPTURE'
    Captured = (Get-Date).ToString('o')
    Hotkey = 'Ctrl+Alt+F10'
    ObservationOnly = $true
    Active = $stateValues.Active
    PlaybackStatus = $stateValues.PlaybackStatus
    Source = $stateValues.Source
    Title = $stateValues.Title
    Artist = $stateValues.Artist
    Album = $stateValues.Album
    ArtworkAvailable = $stateValues.ArtworkAvailable
    AdvertisedArtwork = $advertisedArtwork
    AdvertisedArtworkExists = ($null -ne $advertisedItem)
    AdvertisedArtworkLength = $(if ($advertisedItem) { $advertisedItem.Length } else { $null })
    AdvertisedArtworkLastWriteTime = $(if ($advertisedItem) { $advertisedItem.LastWriteTime.ToString('o') } else { $null })
    AdvertisedArtworkSHA256 = $(if ($advertisedItem) { Get-Sha256Hex -Path $advertisedItem.FullName } else { $null })
    ArtworkSlot = $(if ($advertisedArtwork) { [IO.Path]::GetFileNameWithoutExtension($advertisedArtwork) } else { '' })
    StateFileLastWriteTime = $(if (Test-Path -LiteralPath $statePath) { (Get-Item -LiteralPath $statePath).LastWriteTime.ToString('o') } else { $null })
    RainmeterParsedArtwork = $rainmeterValues.ParsedDashboardArtwork
    RainmeterAppliedArtwork = $rainmeterValues.AppliedArtwork
    RainmeterMeterImageName = $rainmeterValues.MeterImageName
    RainmeterMeterHidden = $rainmeterValues.MeterHidden
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $capturePath 'capture_summary.json') -Encoding UTF8

@(
    "ARTWORK_DIAGNOSTIC_CAPTURE"
    "Captured=$(Get-Date -Format 'o')"
    "CapturePath=$capturePath"
    "ObservationOnly=True"
    'No Rainmeter refresh, collector restart, state rewrite, artwork replacement, playback change, or AVR change was requested.'
) | Set-Content -LiteralPath (Join-Path $capturePath 'README.txt') -Encoding UTF8

Write-Output $capturePath
