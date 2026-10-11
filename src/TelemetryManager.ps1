[CmdletBinding()]
param(
    [string]$Root = 'C:\RainmeterDenon',
    [string]$ManagerMutexName = 'Local\RainmeterDenonTelemetryManager',
    [int]$SupervisionIntervalMilliseconds = 3000,
    [int]$HotkeyRetrySeconds = 60,
    [int]$MaximumCycles = 0
)

$ErrorActionPreference = 'Stop'
$NowPlaying = Join-Path $Root 'NowPlaying'
$Log = Join-Path $Root 'telemetry_manager.log'
$State = Join-Path $Root 'telemetry_manager_status.txt'
$IdentityScript = Join-Path $PSScriptRoot 'Utilities\TelemetryProcessIdentity.ps1'

$DenonScript = Join-Path $Root 'denon_status.ps1'
$RouterScript = Join-Path $NowPlaying 'NowPlayingRouter.ps1'
$DecoderScript = Join-Path $Root 'DecoderCollector.ps1'
$Box1Script = Join-Path $Root 'Box1Collector.ps1'
$WatchdogScript = Join-Path $Root 'AvrWatchdog.ps1'
$HotkeyScript = Join-Path $Root 'Utilities\RainmeterRefreshHotkey.ps1'

$DenonHeartbeat = Join-Path $Root 'denon_heartbeat.txt'
$NowPlayingState = Join-Path $NowPlaying 'now_playing.txt'
$RouterHeartbeat = Join-Path $NowPlaying 'router_heartbeat.txt'
$DecoderHeartbeat = Join-Path $Root 'decoder_heartbeat.txt'
$Box1Heartbeat = Join-Path $Root 'box1_heartbeat.txt'

$routerHeartbeatStaleLogged = $false
$hotkeyPID = $null
$nextHotkeyStartAttempt = [datetime]::MinValue
$cycle = 0
$lastThrottledLog = @{}

if (-not (Test-Path -LiteralPath $IdentityScript -PathType Leaf)) {
    throw "Telemetry process identity helper not found: $IdentityScript"
}
. $IdentityScript

$createdNew = $false
$mutex = [Threading.Mutex]::new($true, $ManagerMutexName, [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    exit 0
}

function Log([string]$Message) {
    try {
        Add-Content -LiteralPath $Log -Value (
            '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
        ) -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Logging failure must never terminate supervision.
    }
}

function Log-Throttled {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Message,
        [int]$MinimumSeconds = 60
    )

    $now = Get-Date
    if (-not $lastThrottledLog.ContainsKey($Key) -or
        ($now - $lastThrottledLog[$Key]).TotalSeconds -ge $MinimumSeconds) {
        Log $Message
        $lastThrottledLog[$Key] = $now
    }
}

function Find-Collector([string]$ScriptPath) {
    @(Get-TelemetryScriptProcesses -ScriptPath $ScriptPath)
}

function Stop-Collector([string]$ScriptPath) {
    foreach ($process in @(Find-Collector $ScriptPath)) {
        if (Stop-TelemetryScriptProcess -Process $process) {
            Log "Stopped PID $($process.ProcessId): $ScriptPath"
        }
    }
}

function Start-Collector([string]$ScriptPath, [string]$Name) {
    try {
        $found = @(Find-Collector $ScriptPath)

        if ($found.Count -gt 1) {
            Log "$Name had $($found.Count) exact copies; restarting cleanly."
            Stop-Collector $ScriptPath
            $found = @()
        }

        if ($found.Count -eq 0 -and (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', ('"{0}"' -f $ScriptPath)
            )
            Log "Started $Name."
            Start-Sleep -Milliseconds 500
        }
    }
    catch {
        Log-Throttled -Key "Start:$ScriptPath" -Message (
            "Failed to supervise $Name. Exception=$($_.Exception.Message)"
        )
    }
}

function Start-HotkeyListener {
    try {
        $found = @(Find-Collector $HotkeyScript | Sort-Object CreationDate, ProcessId)

        if ($found.Count -gt 1) {
            $keeper = $found[0]
            foreach ($duplicate in @($found | Select-Object -Skip 1)) {
                if (Stop-TelemetryScriptProcess -Process $duplicate) {
                    Log "Rejected duplicate Rainmeter refresh hotkey listener PID=$($duplicate.ProcessId); preserved PID=$($keeper.ProcessId)."
                }
            }
            $found = @($keeper)
        }

        if ($found.Count -eq 1) {
            $currentPID = [int]$found[0].ProcessId
            if ($hotkeyPID -ne $currentPID) {
                Log "Healthy existing Rainmeter refresh hotkey listener detected. PID=$currentPID"
                $script:hotkeyPID = $currentPID
            }
            return
        }

        if ($null -ne $hotkeyPID) {
            Log "Rainmeter refresh hotkey listener unexpectedly exited. PreviousPID=$hotkeyPID"
            $script:hotkeyPID = $null
        }

        if ((Get-Date) -lt $nextHotkeyStartAttempt) { return }
        $script:nextHotkeyStartAttempt = (Get-Date).AddSeconds([math]::Max(1, $HotkeyRetrySeconds))

        if (-not (Test-Path -LiteralPath $HotkeyScript -PathType Leaf)) {
            Log-Throttled -Key 'HotkeyMissing' -Message "Rainmeter refresh hotkey listener absent; script not found: $HotkeyScript"
            return
        }

        $process = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $HotkeyScript)
        )
        Log "Rainmeter refresh hotkey listener launch attempted. PID=$($process.Id)"

        Start-Sleep -Milliseconds 1000
        $process.Refresh()
        if ($process.HasExited) {
            Log "Rainmeter refresh hotkey listener launch failed or exited immediately. PID=$($process.Id) ExitCode=$($process.ExitCode)"
            $process.Dispose()
            return
        }

        $script:hotkeyPID = $process.Id
        Log "Started Rainmeter refresh hotkey listener. PID=$hotkeyPID"
        $process.Dispose()
    }
    catch {
        Log-Throttled -Key 'HotkeySupervisionFailure' -Message (
            "Rainmeter refresh hotkey listener supervision failed. Exception=$($_.Exception.Message)"
        )
    }
}

function AgeSeconds([string]$Path) {
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 999999 }
        return ((Get-Date) - (Get-Item -LiteralPath $Path -ErrorAction Stop).LastWriteTime).TotalSeconds
    }
    catch {
        Log-Throttled -Key "Age:$Path" -Message (
            "Could not read freshness for $Path. Exception=$($_.Exception.Message)"
        )
        return 999999
    }
}

function Publish-State([string[]]$Lines) {
    $tempState = "$State.$PID.tmp"

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            [IO.File]::WriteAllLines($tempState, $Lines, [Text.UTF8Encoding]::new($false))
            if (Test-Path -LiteralPath $State -PathType Leaf) {
                [IO.File]::Replace(
                    $tempState,
                    $State,
                    [Management.Automation.Language.NullString]::Value
                )
            }
            else {
                [IO.File]::Move($tempState, $State)
            }
            return $true
        }
        catch {
            if ($attempt -lt 3) { Start-Sleep -Milliseconds 100 }
            else {
                Log-Throttled -Key 'StatePublication' -Message (
                    "Manager status publication failed after $attempt attempts. Exception=$($_.Exception.Message)"
                )
            }
        }
        finally {
            if (Test-Path -LiteralPath $tempState -PathType Leaf) {
                Remove-Item -LiteralPath $tempState -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $false
}

function Write-State([string]$ManagerState = 'Running') {
    try {
        $d = @(Find-Collector $DenonScript)
        $r = @(Find-Collector $RouterScript)
        $a = @(Find-Collector (Join-Path $NowPlaying 'AppleMusicCollector.ps1'))
        $w = @(Find-Collector (Join-Path $NowPlaying 'WiiM-NowPlaying-Bridge.ps1'))
        $x = @(Find-Collector $DecoderScript)
        $b = @(Find-Collector $Box1Script)
        $h = @(Find-Collector $HotkeyScript)

        $activeMetadata = if ($w.Count -eq 1) {
            'WiiM'
        }
        elseif ($a.Count -eq 1) {
            'AppleMusic'
        }
        elseif ($a.Count -gt 1 -or $w.Count -gt 1) {
            'Duplicate'
        }
        else {
            'None'
        }

        $lines = @(
            "Manager=$ManagerState"
            "ManagerPID=$(if ($ManagerState -eq 'Running') { $PID })"

            "DenonCollector=$(if($d.Count -eq 1){'Running'}elseif($d.Count -eq 0){'Stopped'}else{'Duplicate'})"
            "DenonPID=$(($d | Select-Object -ExpandProperty ProcessId) -join ',')"
            "DenonHeartbeatAgeSeconds=$([math]::Round((AgeSeconds $DenonHeartbeat),1))"

            "NowPlayingRouter=$(if($r.Count -eq 1){'Running'}elseif($r.Count -eq 0){'Stopped'}else{'Duplicate'})"
            "RouterPID=$(($r | Select-Object -ExpandProperty ProcessId) -join ',')"
            "ActiveMetadataCollector=$activeMetadata"
            "ApplePID=$(($a | Select-Object -ExpandProperty ProcessId) -join ',')"
            "WiiMPID=$(($w | Select-Object -ExpandProperty ProcessId) -join ',')"
            "NowPlayingStateAgeSeconds=$([math]::Round((AgeSeconds $NowPlayingState),1))"

            "DecoderCollector=$(if($x.Count -eq 1){'Running'}elseif($x.Count -eq 0){'Stopped'}else{'Duplicate'})"
            "DecoderPID=$(($x | Select-Object -ExpandProperty ProcessId) -join ',')"
            "DecoderHeartbeatAgeSeconds=$([math]::Round((AgeSeconds $DecoderHeartbeat),1))"

            "Box1Collector=$(if($b.Count -eq 1){'Running'}elseif($b.Count -eq 0){'Stopped'}else{'Duplicate'})"
            "Box1PID=$(($b | Select-Object -ExpandProperty ProcessId) -join ',')"
            "Box1HeartbeatAgeSeconds=$([math]::Round((AgeSeconds $Box1Heartbeat),1))"

            "RainmeterRefreshHotkey=$(if($h.Count -eq 1){'Running'}elseif($h.Count -eq 0){'Stopped'}else{'Duplicate'})"
            "RainmeterRefreshHotkeyPID=$(($h | Select-Object -ExpandProperty ProcessId) -join ',')"

            "Updated=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        )

        [void](Publish-State $lines)
    }
    catch {
        Log-Throttled -Key 'WriteState' -Message (
            "Manager status collection failed. Exception=$($_.Exception.Message)"
        )
    }
}

New-Item -ItemType Directory -Path $NowPlaying -Force | Out-Null
Log "Telemetry Manager started. PID=$PID"

try {
    while ($MaximumCycles -le 0 -or $cycle -lt $MaximumCycles) {
        $cycle++

        try {
            Start-Collector $DenonScript 'Denon collector'
            Start-Collector $RouterScript 'Now Playing router'
            Start-Collector $DecoderScript 'Decoder collector'
            Start-Collector $Box1Script 'Box 1 collector'
            Start-Collector $WatchdogScript 'AVR health watchdog'
            try {
                $watchdogs = @(Find-Collector $WatchdogScript)
                if ($watchdogs.Count -eq 1 -and
                    ((Get-Date) - $watchdogs[0].CreationDate).TotalSeconds -gt 60 -and
                    (AgeSeconds (Join-Path $Root 'avr_health.json')) -gt 60) {
                    Log 'Watchdog publication stale; restarting isolated watchdog.'
                    Stop-Collector $WatchdogScript
                }
            } catch { Log-Throttled -Key 'WatchdogSupervision' -Message $_.Exception.Message }
            Start-HotkeyListener

            try {
                if ((Find-Collector $DenonScript).Count -eq 1 -and
                    (AgeSeconds $DenonHeartbeat) -gt 12) {
                    Log 'Denon heartbeat stale; restarting collector.'
                    Stop-Collector $DenonScript
                }
            }
            catch {
                Log-Throttled -Key 'DenonSupervision' -Message "Denon supervision failed. Exception=$($_.Exception.Message)"
            }

            try {
                if ((Find-Collector $DecoderScript).Count -eq 1 -and
                    (AgeSeconds $DecoderHeartbeat) -gt 30) {
                    Log 'Decoder heartbeat stale; restarting collector.'
                    Stop-Collector $DecoderScript
                }
            }
            catch {
                Log-Throttled -Key 'DecoderSupervision' -Message "Decoder supervision failed. Exception=$($_.Exception.Message)"
            }

            try {
                $box1Processes = @(Find-Collector $Box1Script)
                if ($box1Processes.Count -eq 1 -and
                    ((Get-Date) - $box1Processes[0].CreationDate).TotalSeconds -gt 12 -and
                    (AgeSeconds $Box1Heartbeat) -gt 12) {
                    Log 'Box 1 heartbeat stale; restarting collector.'
                    Stop-Collector $Box1Script
                }
            }
            catch {
                Log-Throttled -Key 'Box1Supervision' -Message "Box 1 supervision failed. Exception=$($_.Exception.Message)"
            }

            try {
                if ((Test-Path -LiteralPath $RouterHeartbeat -PathType Leaf) -and
                    (Find-Collector $RouterScript).Count -eq 1 -and
                    (AgeSeconds $RouterHeartbeat) -gt 12) {

                    if (-not $routerHeartbeatStaleLogged) {
                        Log 'Now Playing router heartbeat stale; logging only.'
                        $routerHeartbeatStaleLogged = $true
                    }
                }
                else {
                    $routerHeartbeatStaleLogged = $false
                }
            }
            catch {
                Log-Throttled -Key 'RouterSupervision' -Message "Now Playing router supervision failed. Exception=$($_.Exception.Message)"
            }

            Write-State
        }
        catch {
            Log-Throttled -Key 'MainLoop' -Message (
                "Telemetry Manager supervision cycle recovered from an unexpected error. Exception=$($_.Exception.ToString())"
            )
        }

        if ($MaximumCycles -le 0 -or $cycle -lt $MaximumCycles) {
            Start-Sleep -Milliseconds ([math]::Max(100, $SupervisionIntervalMilliseconds))
        }
    }
}
finally {
    Write-State -ManagerState 'Stopped'
    Log "Telemetry Manager stopped. PID=$PID"
    try { $mutex.ReleaseMutex() } catch {}
    try { $mutex.Dispose() } catch {}
}
