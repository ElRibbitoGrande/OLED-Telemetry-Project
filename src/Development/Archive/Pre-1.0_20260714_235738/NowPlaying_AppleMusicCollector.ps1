# Apple Music Now Playing collector for Windows PowerShell 5.1
# Writes C:\RainmeterDenon\NowPlaying\now_playing.txt.
# Artwork export is intentionally deferred; Windows PowerShell 5.1 exposes the
# media session metadata reliably but wraps the artwork stream as an unusable COM object.

$ErrorActionPreference = 'Stop'

$OutputDirectory = 'C:\RainmeterDenon\NowPlaying'
$StatePath = Join-Path $OutputDirectory 'now_playing.txt'
$LogPath = Join-Path $OutputDirectory 'apple_music_collector.log'
$ArtworkPathA = Join-Path $OutputDirectory 'artwork_a.jpg'
$ArtworkPathB = Join-Path $OutputDirectory 'artwork_b.jpg'
$PollMilliseconds = 1000

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Add-Type -AssemblyName System.Runtime.WindowsRuntime

function Await-WinRT {
    param(
        [Parameter(Mandatory)] $Operation,
        [Parameter(Mandatory)] [Type] $ResultType
    )

    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethod -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    if (-not $method) { throw 'Could not locate the WinRT AsTask helper.' }

    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}

# Force-load WinRT types through the Windows PowerShell projection. This is the
# same method that succeeded in the Apple Music probe and does not require a
# separately installed Windows SDK or Windows.winmd file.
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSession, Windows.Media.Control, ContentType=WindowsRuntime]
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType=WindowsRuntime]

$managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$propertiesType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Clean-Value {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return (($Value -replace "`r|`n", ' ') -replace '=', '-').Trim()
}

function Format-Time {
    param([long]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    $span = [TimeSpan]::FromSeconds($Seconds)
    if ($span.TotalHours -ge 1) { return $span.ToString('h\:mm\:ss') }
    return $span.ToString('m\:ss')
}

function Split-AppleMetadata {
    param([string]$Artist, [string]$Album)

    $cleanArtist = Clean-Value $Artist
    $cleanAlbum = Clean-Value $Album

    # Apple Music often reports "Artist — Album" in Artist and leaves Album blank.
    if ([string]::IsNullOrWhiteSpace($cleanAlbum) -and $cleanArtist -match '^(.+?)\s+(?:—|–|-)\s+(.+)$') {
        $cleanArtist = $Matches[1].Trim()
        $cleanAlbum = $Matches[2].Trim()
    }

    return @($cleanArtist, $cleanAlbum)
}


function Normalize-MatchText {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $normalized = $Value.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object Text.StringBuilder
    foreach ($character in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return (($builder.ToString() -replace '[^a-z0-9]+', ' ') -replace '\s+', ' ').Trim()
}

function Get-AppleArtwork {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Artist,
        [string]$Album
    )

    if ([string]::IsNullOrWhiteSpace($Title) -or [string]::IsNullOrWhiteSpace($Artist)) { return '' }

    $query = [Uri]::EscapeDataString("$Title $Artist")
    $url = "https://itunes.apple.com/search?term=$query&media=music&entity=song&limit=25"
    $headers = @{ 'User-Agent' = 'RainmeterDenon-NowPlaying/1.0' }
    $response = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 10 -ErrorAction Stop
    if (-not $response.results) { return '' }

    $wantedTitle = Normalize-MatchText $Title
    $wantedArtist = Normalize-MatchText $Artist
    $wantedAlbum = Normalize-MatchText $Album

    $best = $null
    $bestScore = -1
    foreach ($result in @($response.results)) {
        $resultTitle = Normalize-MatchText ([string]$result.trackName)
        $resultArtist = Normalize-MatchText ([string]$result.artistName)
        $resultAlbum = Normalize-MatchText ([string]$result.collectionName)
        $score = 0

        if ($resultTitle -eq $wantedTitle) { $score += 100 }
        elseif ($resultTitle -like "*$wantedTitle*" -or $wantedTitle -like "*$resultTitle*") { $score += 55 }

        if ($resultArtist -eq $wantedArtist) { $score += 80 }
        elseif ($resultArtist -like "*$wantedArtist*" -or $wantedArtist -like "*$resultArtist*") { $score += 40 }

        if ($wantedAlbum) {
            if ($resultAlbum -eq $wantedAlbum) { $score += 45 }
            elseif ($resultAlbum -like "*$wantedAlbum*" -or $wantedAlbum -like "*$resultAlbum*") { $score += 20 }
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $result
        }
    }

    if (-not $best -or $bestScore -lt 100 -or [string]::IsNullOrWhiteSpace([string]$best.artworkUrl100)) {
        return ''
    }

    $artUrl = [string]$best.artworkUrl100
    $artUrl = $artUrl -replace '100x100bb', '600x600bb'
    $destination = if ($script:artworkToggle) { $ArtworkPathA } else { $ArtworkPathB }
    $script:artworkToggle = -not $script:artworkToggle
    $temporary = "$destination.tmp"

    Invoke-WebRequest -Uri $artUrl -Headers $headers -OutFile $temporary -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
    if ((Test-Path -LiteralPath $temporary) -and (Get-Item -LiteralPath $temporary).Length -gt 1024) {
        Move-Item -LiteralPath $temporary -Destination $destination -Force
        return $destination
    }

    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    return ''
}

function Get-AppleMusicSnapshot {
    $manager = Await-WinRT -Operation ($managerType::RequestAsync()) -ResultType $managerType
    $sessions = @($manager.GetSessions())

    $appleSessions = @($sessions | Where-Object {
        $_.SourceAppUserModelId -match '(?i)apple.*music|applemusic'
    })

    if ($appleSessions.Count -eq 0) {
        return [pscustomobject]@{
            Found = $false; Playing = $false; SourceApp = ''; Title = ''; Artist = ''; Album = '';
            PositionSeconds = 0L; DurationSeconds = 0L; ArtworkAvailable = $false
        }
    }

    $session = $appleSessions | Where-Object {
        ([string]$_.GetPlaybackInfo().PlaybackStatus) -eq 'Playing'
    } | Select-Object -First 1

    if (-not $session) { $session = $appleSessions | Select-Object -First 1 }

    $playback = $session.GetPlaybackInfo()
    $timeline = $session.GetTimelineProperties()
    $properties = Await-WinRT -Operation ($session.TryGetMediaPropertiesAsync()) -ResultType $propertiesType

    return [pscustomobject]@{
        Found = $true
        Playing = (([string]$playback.PlaybackStatus) -eq 'Playing')
        SourceApp = [string]$session.SourceAppUserModelId
        Title = [string]$properties.Title
        Artist = [string]$properties.Artist
        Album = [string]$properties.AlbumTitle
        PositionSeconds = [Math]::Max(0L, [long]$timeline.Position.TotalSeconds)
        DurationSeconds = [Math]::Max(0L, [long]$timeline.EndTime.TotalSeconds)
        ArtworkAvailable = ($null -ne $properties.Thumbnail)
    }
}

function Write-State {
    param($Snapshot)

    $active = if ($Snapshot.Found -and $Snapshot.Playing) { 1 } else { 0 }
    $parts = Split-AppleMetadata -Artist $Snapshot.Artist -Album $Snapshot.Album
    $artist = $parts[0]
    $album = $parts[1]

    # Apple Music may alternate between composite and separated metadata during a track.
    # Keep each field on a fixed row and retain the last non-empty normalized values
    # until the title changes, preventing visible artist/album oscillation.
    if ($Snapshot.Title -ne $script:lastTitle) {
        $script:lastTitle = $Snapshot.Title
        $script:stableArtist = ''
        $script:stableAlbum = ''
    }
    if (-not [string]::IsNullOrWhiteSpace($artist)) { $script:stableArtist = $artist }
    if (-not [string]::IsNullOrWhiteSpace($album)) { $script:stableAlbum = $album }
    $artist = $script:stableArtist
    $album = $script:stableAlbum

    $trackKey = '{0}|{1}|{2}' -f (Clean-Value $Snapshot.Title), $artist, $album
    if ($active -eq 1 -and $trackKey -ne $script:lastArtworkTrackKey) {
        $script:lastArtworkTrackKey = $trackKey
        $script:currentArtwork = ''
        try {
            $script:currentArtwork = Get-AppleArtwork -Title (Clean-Value $Snapshot.Title) -Artist $artist -Album $album
            if ($script:currentArtwork) { Write-Log "Artwork saved for: $trackKey" }
            else { Write-Log "No confident artwork match for: $trackKey" }
        }
        catch {
            Write-Log "Artwork lookup failed for '$trackKey': $($_.Exception.Message)"
        }
    }
    elseif ($active -eq 0) {
        $script:currentArtwork = ''
    }

    $position = [long]$Snapshot.PositionSeconds
    $duration = [long]$Snapshot.DurationSeconds
    $progress = if ($duration -gt 0) {
        [Math]::Min(100, [Math]::Max(0, [Math]::Round(($position / $duration) * 100, 1)))
    } else { 0 }

    $lines = @(
        "Active=$active"
        'Source=Apple Music'
        "Title=$(Clean-Value $Snapshot.Title)"
        "Artist=$artist"
        "Album=$album"
        "PositionSeconds=$position"
        "DurationSeconds=$duration"
        "Position=$(Format-Time $position)"
        "Duration=$(Format-Time $duration)"
        "Progress=$progress"
        "ArtworkAvailable=$(if ($Snapshot.ArtworkAvailable) { 1 } else { 0 })"
        "Artwork=$($script:currentArtwork)"
        "Updated=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    )

    $temp = "$StatePath.tmp"
    [System.IO.File]::WriteAllLines($temp, $lines, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $StatePath -Force
}

Write-Log 'Collector v5 with iTunes artwork lookup started.'
$lastError = ''
$lastTitle = ''
$stableArtist = ''
$stableAlbum = ''
$lastArtworkTrackKey = ''
$currentArtwork = ''
$artworkToggle = $false

while ($true) {
    try {
        $snapshot = Get-AppleMusicSnapshot
        Write-State -Snapshot $snapshot
        $lastError = ''
    }
    catch {
        $message = $_.Exception.Message
        if ($message -ne $lastError) {
            Write-Log "Read failure: $message"
            $lastError = $message
        }

        Write-State -Snapshot ([pscustomobject]@{
            Found = $false; Playing = $false; Title = ''; Artist = ''; Album = '';
            PositionSeconds = 0L; DurationSeconds = 0L; ArtworkAvailable = $false
        })
    }

    Start-Sleep -Milliseconds $PollMilliseconds
}
