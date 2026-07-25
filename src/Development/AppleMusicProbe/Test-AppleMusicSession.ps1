# Apple Music / Windows media-session diagnostic probe
# Compatible with Windows PowerShell 5.1 on Windows 11.
# It does not alter Rainmeter or the Denon telemetry files.

$ErrorActionPreference = 'Stop'

# Required by Windows PowerShell 5.1 for WinRT AsTask helpers.
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

    if (-not $method) {
        throw 'Could not locate the WinRT AsTask helper.'
    }

    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}

function Save-WinRTThumbnail {
    param(
        [Parameter(Mandatory)] $ThumbnailReference,
        [Parameter(Mandatory)] [string] $Destination
    )

    $streamType = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType=WindowsRuntime]
    $randomAccessStream = Await-WinRT -Operation ($ThumbnailReference.OpenReadAsync()) -ResultType $streamType

    # Avoid WindowsRuntimeStreamExtensions.AsStreamForRead. Windows PowerShell
    # 5.1 can see the method but cannot bind its WinRT COM wrapper reliably.
    # DataReader reads the same stream directly and returns ordinary bytes.
    $inputStream = $randomAccessStream.GetInputStreamAt(0)
    $reader = [Windows.Storage.Streams.DataReader]::new($inputStream)
    $length = [uint32]$randomAccessStream.Size

    if ($length -eq 0) {
        throw 'Apple Music reported artwork, but the artwork stream was empty.'
    }

    $loaded = Await-WinRT -Operation ($reader.LoadAsync($length)) -ResultType ([uint32])
    if ($loaded -eq 0) {
        throw 'Apple Music artwork could not be read from the media session.'
    }

    $bytes = New-Object byte[] $loaded
    $reader.ReadBytes($bytes)
    [System.IO.File]::WriteAllBytes($Destination, $bytes)

    if (-not (Test-Path -LiteralPath $Destination)) {
        throw "Artwork file was not created: $Destination"
    }

    $saved = Get-Item -LiteralPath $Destination
    if ($saved.Length -le 0) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw 'Artwork file was created but contained zero bytes.'
    }

    return $saved.Length
}

# Force-load the WinRT types used below.
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSession, Windows.Media.Control, ContentType=WindowsRuntime]
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType=WindowsRuntime]

$managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$sessionType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSession]
$propertiesType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]

$manager = Await-WinRT -Operation ($managerType::RequestAsync()) -ResultType $managerType
$sessions = @($manager.GetSessions())

Write-Host ''
Write-Host ('Media sessions found: {0}' -f $sessions.Count) -ForegroundColor Cyan
Write-Host ''

if ($sessions.Count -eq 0) {
    Write-Host 'No Windows media sessions are currently available.' -ForegroundColor Yellow
    Write-Host 'Start playback in Apple Music and run this script again.'
    exit 2
}

$results = foreach ($session in $sessions) {
    $properties = Await-WinRT -Operation ($session.TryGetMediaPropertiesAsync()) -ResultType $propertiesType
    $playback = $session.GetPlaybackInfo()
    $timeline = $session.GetTimelineProperties()

    [pscustomobject]@{
        SourceApp       = $session.SourceAppUserModelId
        PlaybackStatus = [string]$playback.PlaybackStatus
        Title           = $properties.Title
        Artist          = $properties.Artist
        Album           = $properties.AlbumTitle
        TrackNumber     = $properties.TrackNumber
        Position        = $timeline.Position
        StartTime       = $timeline.StartTime
        EndTime         = $timeline.EndTime
        HasThumbnail    = ($null -ne $properties.Thumbnail)
        Session         = $session
        Properties      = $properties
    }
}

$results |
    Select-Object SourceApp, PlaybackStatus, Title, Artist, Album, Position, EndTime, HasThumbnail |
    Format-List

$apple = @($results | Where-Object {
    $_.SourceApp -match '(?i)apple.*music|applemusic'
})

Write-Host ''
if ($apple.Count -eq 0) {
    Write-Host 'Apple Music session: NOT FOUND' -ForegroundColor Yellow
    Write-Host 'Leave Apple Music open, start a song, and run the script again.'
    exit 3
}

$chosen = @($apple | Where-Object { $_.PlaybackStatus -eq 'Playing' } | Select-Object -First 1)
if (-not $chosen) {
    $chosen = $apple | Select-Object -First 1
}

Write-Host 'Apple Music session: FOUND' -ForegroundColor Green
Write-Host ('Actually playing: {0}' -f ($chosen.PlaybackStatus -eq 'Playing'))
Write-Host ('Source app ID:    {0}' -f $chosen.SourceApp)
Write-Host ('Title:            {0}' -f $chosen.Title)
Write-Host ('Artist:           {0}' -f $chosen.Artist)
Write-Host ('Album:            {0}' -f $chosen.Album)
Write-Host ('Position:         {0}' -f $chosen.Position)
Write-Host ('Duration/end:     {0}' -f $chosen.EndTime)
Write-Host ('Artwork present:  {0}' -f $chosen.HasThumbnail)

if ($chosen.HasThumbnail) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $artPath = Join-Path $desktop 'apple_music_probe_artwork.jpg'
    try {
        $artBytes = Save-WinRTThumbnail -ThumbnailReference $chosen.Properties.Thumbnail -Destination $artPath
        Write-Host ('Artwork saved:    {0}' -f $artPath) -ForegroundColor Green
        Write-Host ('Artwork bytes:    {0}' -f $artBytes) -ForegroundColor Green
    }
    catch {
        Write-Warning ('Metadata worked, but artwork export failed: {0}' -f $_.Exception.Message)
    }
}

Write-Host ''
Write-Host 'Probe complete. Copy the complete output back into the chat.' -ForegroundColor Cyan
