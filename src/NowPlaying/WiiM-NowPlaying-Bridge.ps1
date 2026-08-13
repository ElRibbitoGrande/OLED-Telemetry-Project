param(
    [string]$WiiMIP = "192.168.0.249",
    [string]$NowPlayingDir = "C:\RainmeterDenon\NowPlaying",
    [int]$PollSeconds = 2
)

$ErrorActionPreference = "Stop"

function Convert-HexToText {
    param([AllowNull()][string]$Hex)

    if ([string]::IsNullOrWhiteSpace($Hex)) { return "" }
    if ($Hex -notmatch '^[0-9A-Fa-f]+$' -or ($Hex.Length % 2) -ne 0) { return $Hex }

    try {
        $bytes = for ($i = 0; $i -lt $Hex.Length; $i += 2) {
            [Convert]::ToByte($Hex.Substring($i, 2), 16)
        }
        return [Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
        return $Hex
    }
}

function Escape-LineValue {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "" }
    return ($Value -replace "`r", " " -replace "`n", " ").Trim()
}

function Write-AtomicText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $tempPath = "$Path.tmp"
    [IO.File]::WriteAllText($tempPath, $Content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function Format-Time {
    param([long]$Seconds)

    if ($Seconds -lt 0) { $Seconds = 0 }
    $minutes = [math]::Floor($Seconds / 60)
    $remaining = $Seconds % 60
    return ("{0}:{1:00}" -f $minutes, $remaining)
}

# WiiM uses HTTPS with a local/self-signed certificate.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint,
        X509Certificate certificate,
        WebRequest request,
        int certificateProblem) {
        return true;
    }
}
"@
    [Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$statusUrl = "https://$WiiMIP/httpapi.asp?command=getPlayerStatus"
$metaUrl   = "https://$WiiMIP/httpapi.asp?command=getMetaInfo"

New-Item -ItemType Directory -Path $NowPlayingDir -Force | Out-Null
. (Join-Path $PSScriptRoot 'NowPlayingDiagnostic.ps1')

$nowPlayingPath = Join-Path $NowPlayingDir "now_playing.txt"
$artworkPath = Join-Path $NowPlayingDir "wiim_artwork.jpg"
$lastTrackId = ""
$lastPublishedArtist = ""
$artistLossOutstanding = $false
$lastDiagnosticSignature = ""
$nextDiagnosticHeartbeat = Get-Date
$diagnosticSequence = 0
$lastCollectorError = ""

function Write-WiiMStateDiagnostic {
    param(
        [int]$Active,
        [string]$Source,
        [string]$Title,
        [string]$Artist,
        [string]$Album,
        [int]$ArtworkAvailable,
        [string]$Artwork,
        [bool]$CollectorFresh,
        [string]$Reason
    )

    try {
        $script:diagnosticSequence++
        $signature = "$Active|$Source|$Title|$Artist|$Album|$ArtworkAvailable|$Artwork"
        $now = Get-Date
        if ($signature -ne $script:lastDiagnosticSignature -or $now -ge $script:nextDiagnosticHeartbeat) {
            $event = if ($signature -ne $script:lastDiagnosticSignature) { 'COLLECTOR_STATE' } else { 'STATE_HEARTBEAT' }
            Write-NowPlayingDiagnostic -Component 'WiiMCollector' -Event $event -Fields @{
                active = $Active; source = $Source; sourceIdentity = 'LYR+'
                title = $Title; rawArtist = $Artist; artist = $Artist; album = $Album
                artworkAvailable = $ArtworkAvailable; artwork = $Artwork
                collectorFresh = $CollectorFresh; lastKnownGoodArtist = 'none'
                stateWrite = 'success'; statePath = $nowPlayingPath
                stateFileTimestamp = (Get-Item -LiteralPath $nowPlayingPath).LastWriteTime.ToString('o')
                sequence = $script:diagnosticSequence; reason = $Reason
            }
            $script:lastDiagnosticSignature = $signature
            $script:nextDiagnosticHeartbeat = $now.AddSeconds(30)
        }

    if (-not [string]::IsNullOrWhiteSpace($script:lastPublishedArtist) -and
        [string]::IsNullOrWhiteSpace($Artist)) {
        $lossEvent = if ($Active -eq 1 -or -not $CollectorFresh) { 'ARTIST_LOST' } else { 'ARTIST_CLEARED_INTENTIONAL' }
        Write-NowPlayingDiagnostic -Component 'WiiMCollector' -Event $lossEvent -Fields @{
            active = $Active; source = $Source; sourceIdentity = 'LYR+'; title = $Title
            previousArtist = $script:lastPublishedArtist; artist = ''; album = $Album
            lastKnownGoodArtist = 'cleared'; reason = $Reason
            stateWrite = 'success'; sequence = $script:diagnosticSequence
        }
        if ($lossEvent -eq 'ARTIST_LOST') { $script:artistLossOutstanding = $true }
    }
    elseif ($script:artistLossOutstanding -and -not [string]::IsNullOrWhiteSpace($Artist)) {
        Write-NowPlayingDiagnostic -Component 'WiiMCollector' -Event 'ARTIST_RESTORED' -Fields @{
            active = $Active; source = $Source; sourceIdentity = 'LYR+'; title = $Title
            previousArtist = $script:lastPublishedArtist; artist = $Artist; album = $Album
            stateWrite = 'success'; sequence = $script:diagnosticSequence
        }
        $script:artistLossOutstanding = $false
    }
        $script:lastPublishedArtist = $Artist
    }
    catch {
        # Diagnostics must never affect state publication or the polling loop.
    }
}

Write-NowPlayingDiagnostic -Component 'WiiMCollector' -Event 'COLLECTOR_STARTED' -Fields @{
    source = 'WiiM'; sourceIdentity = 'LYR+'; statePath = $nowPlayingPath; pollSeconds = $PollSeconds
}

Write-Host "Polling WiiM at $WiiMIP every $PollSeconds seconds."
Write-Host "Writing Rainmeter-compatible output to:"
Write-Host "  $nowPlayingPath"
Write-Host "Press Ctrl+C to stop."
Write-Host ""
Write-Warning "During this test, stop the Apple Music metadata poller so it does not overwrite now_playing.txt."

while ($true) {
    try {
        $status = Invoke-RestMethod -Uri $statusUrl -Method Get -TimeoutSec 5
        $metaResponse = Invoke-RestMethod -Uri $metaUrl -Method Get -TimeoutSec 5
        $meta = $metaResponse.metaData

        $title  = if ($meta.title)  { [string]$meta.title }  else { Convert-HexToText ([string]$status.Title) }
        $artist = if ($meta.artist) { [string]$meta.artist } else { Convert-HexToText ([string]$status.Artist) }
        $album  = if ($meta.album)  { [string]$meta.album }  else { Convert-HexToText ([string]$status.Album) }

        $trackId = [string]$meta.trackId
        $artUrl = [string]$meta.albumArtURI

        $positionSeconds = 0
        try {
            $positionMilliseconds = [long]([string]$status.curpos)
            $positionSeconds = [math]::Floor($positionMilliseconds / 1000)
        }
        catch { $positionSeconds = 0 }

        $durationSeconds = 0
        try {
            $durationMilliseconds = [long]([string]$status.totlen)
            $durationSeconds = [math]::Floor($durationMilliseconds / 1000)
        }
        catch { $durationSeconds = 0 }

        $progress = 0
        if ($durationSeconds -gt 0) {
            $progress = [math]::Min(100, [math]::Max(0, [math]::Round(($positionSeconds / $durationSeconds) * 100, 1)))
        }

        $artworkAvailable = 0
        if (-not [string]::IsNullOrWhiteSpace($artUrl)) {
            if (($trackId -ne $lastTrackId) -or -not (Test-Path -LiteralPath $artworkPath)) {
                try {
                    $tempArt = "$artworkPath.tmp"
                    Invoke-WebRequest -Uri $artUrl -OutFile $tempArt -TimeoutSec 10
                    Move-Item -LiteralPath $tempArt -Destination $artworkPath -Force
                    $lastTrackId = $trackId
                }
                catch {
                    Write-Warning "Artwork download failed: $($_.Exception.Message)"
                }
            }

            if (Test-Path -LiteralPath $artworkPath) {
                $artworkAvailable = 1
            }
        }

        # "Active" means valid WiiM metadata is available. It remains active while paused
        # so Rainmeter keeps showing the current track.
        $active = if (-not [string]::IsNullOrWhiteSpace($title) -or
                      -not [string]::IsNullOrWhiteSpace($artist)) { 1 } else { 0 }

        $source = switch ([string]$status.vendor) {
            "Prime" { "Amazon Music" }
            default {
                if ([string]::IsNullOrWhiteSpace([string]$status.vendor)) { "WiiM" }
                else { [string]$status.vendor }
            }
        }

        $content = @(
            "Active=$active"
            "Source=$(Escape-LineValue $source)"
            "Title=$(Escape-LineValue $title)"
            "Artist=$(Escape-LineValue $artist)"
            "Album=$(Escape-LineValue $album)"
            "PositionSeconds=$positionSeconds"
            "DurationSeconds=$durationSeconds"
            "Position=$(Format-Time $positionSeconds)"
            "Duration=$(if ($durationSeconds -gt 0) { Format-Time $durationSeconds } else { '' })"
            "Progress=$progress"
            "ArtworkAvailable=$artworkAvailable"
            "Artwork=$(if ($artworkAvailable -eq 1) { Escape-LineValue $artworkPath } else { '' })"
            ""
        ) -join "`r`n"

        Write-AtomicText -Path $nowPlayingPath -Content $content
        Write-WiiMStateDiagnostic -Active $active -Source $source -Title (Escape-LineValue $title) `
            -Artist (Escape-LineValue $artist) -Album (Escape-LineValue $album) `
            -ArtworkAvailable $artworkAvailable `
            -Artwork $(if ($artworkAvailable -eq 1) { $artworkPath } else { '' }) `
            -CollectorFresh $true -Reason 'WiiM query succeeded'
        if (-not [string]::IsNullOrWhiteSpace($lastCollectorError)) {
            Write-NowPlayingDiagnostic -Component 'WiiMCollector' -Event 'COLLECTOR_RECOVERED' -Fields @{
                source = $source; sourceIdentity = 'LYR+'; collectorFresh = $true
                previousException = $lastCollectorError
            }
            $lastCollectorError = ''
        }

        Write-Host ("{0} | {1} - {2}" -f (Get-Date -Format "HH:mm:ss"), $artist, $title)
    }
    catch {
        $failureMessage = $_.Exception.Message
        if ($failureMessage -ne $lastCollectorError) {
            Write-NowPlayingDiagnostic -Component 'WiiMCollector' -Event 'COLLECTOR_EXCEPTION' -Fields @{
                source = 'WiiM'; sourceIdentity = 'LYR+'; collectorFresh = $false
                exception = $failureMessage
            }
            $lastCollectorError = $failureMessage
        }
        $content = @(
            "Active=0"
            "Source=WiiM"
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

        try {
            Write-AtomicText -Path $nowPlayingPath -Content $content
            Write-WiiMStateDiagnostic -Active 0 -Source 'WiiM' -Title '' -Artist '' -Album '' `
                -ArtworkAvailable 0 -Artwork '' -CollectorFresh $false `
                -Reason "WiiM query failed: $failureMessage"
        }
        catch {
            Write-NowPlayingDiagnostic -Component 'WiiMCollector' -Event 'STATE_WRITE_FAILED' -Fields @{
                active = 0; source = 'WiiM'; sourceIdentity = 'LYR+'; title = ''; artist = ''; album = ''
                collectorFresh = $false; stateWrite = 'failure'; statePath = $nowPlayingPath
                exception = $_.Exception.Message; collectorException = $failureMessage
            }
            throw
        }
        Write-Warning "WiiM query failed: $failureMessage"
    }

    Start-Sleep -Seconds $PollSeconds
}
