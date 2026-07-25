$ErrorActionPreference = 'Stop'
$Root = 'C:\RainmeterDenon'
$NowPlaying = Join-Path $Root 'NowPlaying'
$Log = Join-Path $Root 'telemetry_manager.log'
$State = Join-Path $Root 'telemetry_manager_status.txt'

$DenonScript = Join-Path $Root 'denon_status.ps1'
$RouterScript = Join-Path $NowPlaying 'NowPlayingRouter.ps1'
$DecoderScript = Join-Path $Root 'DecoderCollector.ps1'

$DenonHeartbeat = Join-Path $Root 'denon_heartbeat.txt'
$NowPlayingState = Join-Path $NowPlaying 'now_playing.txt'
$DecoderHeartbeat = Join-Path $Root 'decoder_heartbeat.txt'

$createdNew = $false
$mutex = [Threading.Mutex]::new($true, 'Local\RainmeterDenonTelemetryManager', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

function Log([string]$Message) {
    Add-Content -LiteralPath $Log -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message) -Encoding UTF8
}

function Find-Collector([string]$Pattern) {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match $Pattern })
}

function Stop-Collector([string]$Pattern) {
    foreach ($p in Find-Collector $Pattern) {
        try {
            Invoke-CimMethod -InputObject $p -MethodName Terminate | Out-Null
            Log "Stopped PID $($p.ProcessId): $($p.CommandLine)"
        }
        catch {}
    }
}

function Start-Collector([string]$ScriptPath, [string]$Pattern, [string]$Name) {
    $found = @(Find-Collector $Pattern)
    $foundCount = @($found).Count

    if ($foundCount -gt 1) {
        Log "$Name had $foundCount copies; restarting cleanly."
        Stop-Collector $Pattern
        $found = @()
    }

    if (@($found).Count -eq 0 -and (Test-Path $ScriptPath)) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $ScriptPath)
        )
        Log "Started $Name."
        Start-Sleep -Milliseconds 500
    }
}

function AgeSeconds([string]$Path) {
    if (-not (Test-Path $Path)) { return 999999 }
    return ((Get-Date) - (Get-Item $Path).LastWriteTime).TotalSeconds
}

function Write-State {
    $d = @(Find-Collector 'denon_status\.ps1')
    $r = @(Find-Collector 'NowPlayingRouter\.ps1')
    $a = @(Find-Collector 'AppleMusicCollector\.ps1')
    $w = @(Find-Collector 'WiiM-NowPlaying-Bridge\.ps1')
    $x = @(Find-Collector 'DecoderCollector\.ps1')

    $dCount = @($d).Count
    $rCount = @($r).Count
    $aCount = @($a).Count
    $wCount = @($w).Count
    $xCount = @($x).Count

    $activeMetadata = if ($wCount -eq 1) {
        'WiiM'
    }
    elseif ($aCount -eq 1) {
        'AppleMusic'
    }
    elseif ($aCount -gt 1 -or $wCount -gt 1) {
        'Duplicate'
    }
    else {
        'None'
    }

    $lines = @(
        "Manager=Running"
        "ManagerPID=$PID"

        "DenonCollector=$(if($dCount -eq 1){'Running'}elseif($dCount -eq 0){'Stopped'}else{'Duplicate'})"
        "DenonPID=$(($d | Select-Object -ExpandProperty ProcessId) -join ',')"
        "DenonHeartbeatAgeSeconds=$([math]::Round((AgeSeconds $DenonHeartbeat),1))"

        "NowPlayingRouter=$(if($rCount -eq 1){'Running'}elseif($rCount -eq 0){'Stopped'}else{'Duplicate'})"
        "RouterPID=$(($r | Select-Object -ExpandProperty ProcessId) -join ',')"
        "ActiveMetadataCollector=$activeMetadata"
        "ApplePID=$(($a | Select-Object -ExpandProperty ProcessId) -join ',')"
        "WiiMPID=$(($w | Select-Object -ExpandProperty ProcessId) -join ',')"
        "NowPlayingStateAgeSeconds=$([math]::Round((AgeSeconds $NowPlayingState),1))"

        "DecoderCollector=$(if($xCount -eq 1){'Running'}elseif($xCount -eq 0){'Stopped'}else{'Duplicate'})"
        "DecoderPID=$(($x | Select-Object -ExpandProperty ProcessId) -join ',')"
        "DecoderHeartbeatAgeSeconds=$([math]::Round((AgeSeconds $DecoderHeartbeat),1))"

        "Updated=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    )

    [IO.File]::WriteAllLines($State, $lines, [Text.UTF8Encoding]::new($false))
}

New-Item -ItemType Directory -Path $NowPlaying -Force | Out-Null
Log 'Telemetry Manager started.'

try {
    while ($true) {
        Start-Collector $DenonScript 'denon_status\.ps1' 'Denon collector'
        Start-Collector $RouterScript 'NowPlayingRouter\.ps1' 'Now Playing router'
        Start-Collector $DecoderScript 'DecoderCollector\.ps1' 'Decoder collector'

        # The router owns and switches the Apple Music and WiiM collectors.
        # The manager supervises only the router itself, not its child collector.
        if ((Find-Collector 'denon_status\.ps1').Count -eq 1 -and
            (AgeSeconds $DenonHeartbeat) -gt 12) {
            Log 'Denon heartbeat stale; restarting collector.'
            Stop-Collector 'denon_status\.ps1'
        }

        if ((Find-Collector 'DecoderCollector\.ps1').Count -eq 1 -and
            (AgeSeconds $DecoderHeartbeat) -gt 30) {
            Log 'Decoder heartbeat stale; restarting collector.'
            Stop-Collector 'DecoderCollector\.ps1'
        }

        Write-State
        Start-Sleep -Seconds 3
    }
}
finally {
    Log 'Telemetry Manager stopped.'
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}
