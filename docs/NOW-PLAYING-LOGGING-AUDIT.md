# Analog_Floating2 Now Playing logging audit

Audit date: 2026-08-13

## Result

The pre-change implementation did not retain enough evidence to locate an
intermittent missing Artist field. The current evidence does not establish
whether Artist was lost upstream in `now_playing.txt`, in Rainmeter's parsing,
or at the final meter-rendering stage.

The router selects a collector, not an Artist value. The selected Apple Music
or WiiM collector writes the common `NowPlaying\now_playing.txt` file directly.
Analog_Floating2 then parses that file through `DashboardTelemetry.inc`, wraps
the parsed value as `DashboardNowPlayingArtist`, and renders it with the
`AF2NowPlayingArtist` meter.

## Logging that existed before this change

| Component | Existing history | Diagnostic limitation |
|---|---|---|
| `TelemetryManager.ps1` | `C:\RainmeterDenon\telemetry_manager.log` records manager/collector starts, stops, and selected stale-heartbeat events. | It does not record Now Playing fields, write outcomes, collector exceptions, or Rainmeter state. It is append-only. |
| `NowPlayingRouter.ps1` | `C:\RainmeterDenon\NowPlaying\router.log` records collector/source changes and unexpected child exits. It truncates at about 64 KB. | It does not record collector metadata or `now_playing.txt` contents. |
| Apple collector | `apple_music_collector.log` records startup, artwork outcomes, and de-duplicated exception text. | It does not record raw/routed Artist, state transitions, write success, or the stage of a failure. It is append-only. |
| WiiM collector | Console output and warnings only. | There is no durable collector log. |
| Common state | `now_playing.txt` contains only the latest state. | There is no state history. |
| Analog_Floating2 | WebParser and String measures consume Artist. | There was no history of the raw file value versus the parsed Rainmeter measure. |

The live and repository copies of the four audited telemetry scripts had
matching SHA-256 hashes before this change.

Repeated Apple log entries reading `Cannot create a file when that file already
exists` were present on 2026-08-12 and 2026-08-13. The old log labels every
exception from the combined snapshot/write loop as `Read failure`, so it does
not establish whether those failures came from metadata acquisition, artwork,
temporary-file publication, or another operation. It is evidence of a failure,
but not evidence of the Artist-loss boundary or root cause.

## Added diagnostics

PowerShell components write JSON-lines events to:

`C:\RainmeterDenon\Logs\NowPlayingDiagnostic.log`

The file rolls at 3 MB and retains four historical files (`.1` through `.4`).
The shared logger waits at most 100 ms for its cross-process mutex and catches
all logging errors so a diagnostic failure cannot stop or freeze a collector.

Collectors log metadata transitions and a 30-second freshness heartbeat,
including raw Artist, published Artist, title, album, artwork state, active
state, source identity, last-known-good action, state-file timestamp, sequence,
and write outcome. Exceptions are logged once per distinct failure and recovery
is explicit.

The router logs `ROUTER_SELECTION` with the Denon source, selected collector,
input signal, mode, and selection reason.

A hidden Analog_Floating2 Lua measure writes:

`C:\RainmeterDenon\Logs\NowPlayingRainmeter.log`

It compares raw `now_playing.txt` Artist with the parsed
`DashboardNowPlayingArtist` measure. It emits transitions, a 30-second
heartbeat, `RAINMETER_MISMATCH`, and `RAINMETER_MATCH_RESTORED`. It has no
visible meter and does not change presentation. This log rolls at 1 MB and
retains three historical files.

Searchable Artist events are:

- `ARTIST_LOST`
- `ARTIST_RESTORED`
- `ARTIST_CLEARED_INTENTIONAL`
- `RAINMETER_MISMATCH`
- `RAINMETER_MATCH_RESTORED`
- `STATE_WRITE_FAILED`

## Boundary interpretation

- `ARTIST_LOST` with a blank Artist in the collector event and shared file is
  upstream of Rainmeter.
- A nonblank collector/shared-file Artist plus `RAINMETER_MISMATCH` is in the
  Rainmeter parsing path.
- Matching nonblank raw and parsed Artist values while the text is visibly
  absent places the failure after the measure, in meter update/rendering.
- `STATE_WRITE_FAILED`, a missing freshness heartbeat, or a collector exception
  identifies a publication or collector-liveness failure without requiring a
  guess from a later restart.

## Callers, files, timeouts, and isolation

- `TelemetryManager.ps1` launches and supervises `NowPlayingRouter.ps1`.
- The router launches exactly one of `AppleMusicCollector.ps1` and
  `WiiM-NowPlaying-Bridge.ps1` according to Denon `Source`.
- Analog_Floating2 is the only current repository caller of
  `DashboardState.inc` and the new hidden Lua probe.
- Collectors write `now_playing.txt` and artwork. The router writes its
  heartbeat/log and writes an inactive state for unsupported sources.
- The capture helper reads state/log files and writes only a timestamped
  evidence bundle under the current user's local application-data directory.
- WiiM status and metadata requests each have a 5-second timeout; artwork has a
  10-second timeout. Apple artwork lookup has a 10-second timeout and artwork
  download has a 15-second timeout. The WinRT asynchronous bridge waits without
  a defined timeout; that remains a diagnostic risk.
- Router, Apple, WiiM, Denon, and decoder collectors are separate processes.
  The new logger is best-effort and bounded, so one failed collector or logger
  cannot block unrelated display elements.

The WiiM script already contained a process-wide certificate-validation bypass
for Windows PowerShell 5.1. This change neither expands nor executes that
behavior. It should be replaced by a scoped, pinned certificate approach in a
separate reviewed change before any new deployment that changes WiiM network
handling.

## Failure capture command

Run this before `RestartTelemetry` or a Rainmeter refresh:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\OLED-Telemetry-Project\diagnostics\Capture-NowPlayingFailure.ps1"
```

The command prints its output directory. By default it creates a timestamped
folder under:

`%LOCALAPPDATA%\OLED-Telemetry\NowPlayingCaptures`

It copies current Now Playing, Denon, router heartbeat, and manager state;
records file timestamps and SHA-256 hashes; captures recent diagnostic,
Rainmeter, router, Apple, and manager log tails; and attempts a read-only
process inventory. Lack of permission for process command lines is recorded in
the bundle instead of aborting capture. It does not restart telemetry, refresh
Rainmeter, or write collector state.

## Deployment and rollback

No deployment was performed as part of this audit.

Deployment must back up the exact live targets first, then copy only:

- `src\NowPlaying\NowPlayingDiagnostic.ps1`
- `src\NowPlaying\NowPlayingRouter.ps1`
- `src\NowPlaying\AppleMusicCollector.ps1`
- `src\NowPlaying\WiiM-NowPlaying-Bridge.ps1`
- `src\@Resources\Includes\DashboardState.inc` to Analog_Floating2's
  `@Resources\Includes` directory
- `src\@Resources\Scripts\NowPlayingDiagnostic.lua` to Analog_Floating2's
  `@Resources\Scripts` directory

After copying, compare SHA-256 hashes for every source/destination pair. Stop
only the router and its active child collector; the existing manager will
restart the router. Refresh only the `Analog_Floating2` Rainmeter config to load
the hidden probe. Do not change or refresh production `Analog_Floating.ini`.

Rollback is the reverse: stop the router and child, restore the six timestamped
backup files (removing only the two newly introduced files if they did not exist
before deployment), verify hashes against the backup, allow the manager to
restart the router, and refresh only `Analog_Floating2`.

Use the following deployment commands from an elevated PowerShell prompt. They
create one rollback directory and do not touch `Analog_Floating.ini`:

```powershell
$repoRoot = 'C:\OLED-Telemetry-Project'
$liveRoot = 'C:\RainmeterDenon'
$skinRoot = 'C:\Users\timmeh\OneDrive\Documents\Rainmeter\Skins\Analog_Floating2'
$backupRoot = Join-Path $liveRoot ('Backups\now-playing-diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path (Join-Path $backupRoot 'NowPlaying') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $backupRoot 'Skin\Includes') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $backupRoot 'Skin\Scripts') -Force | Out-Null

$deployMap = @(
    @{ Source = "$repoRoot\src\NowPlaying\NowPlayingDiagnostic.ps1"; Destination = "$liveRoot\NowPlaying\NowPlayingDiagnostic.ps1"; Backup = "$backupRoot\NowPlaying\NowPlayingDiagnostic.ps1" },
    @{ Source = "$repoRoot\src\NowPlaying\NowPlayingRouter.ps1"; Destination = "$liveRoot\NowPlaying\NowPlayingRouter.ps1"; Backup = "$backupRoot\NowPlaying\NowPlayingRouter.ps1" },
    @{ Source = "$repoRoot\src\NowPlaying\AppleMusicCollector.ps1"; Destination = "$liveRoot\NowPlaying\AppleMusicCollector.ps1"; Backup = "$backupRoot\NowPlaying\AppleMusicCollector.ps1" },
    @{ Source = "$repoRoot\src\NowPlaying\WiiM-NowPlaying-Bridge.ps1"; Destination = "$liveRoot\NowPlaying\WiiM-NowPlaying-Bridge.ps1"; Backup = "$backupRoot\NowPlaying\WiiM-NowPlaying-Bridge.ps1" },
    @{ Source = "$repoRoot\src\@Resources\Includes\DashboardState.inc"; Destination = "$skinRoot\@Resources\Includes\DashboardState.inc"; Backup = "$backupRoot\Skin\Includes\DashboardState.inc" },
    @{ Source = "$repoRoot\src\@Resources\Scripts\NowPlayingDiagnostic.lua"; Destination = "$skinRoot\@Resources\Scripts\NowPlayingDiagnostic.lua"; Backup = "$backupRoot\Skin\Scripts\NowPlayingDiagnostic.lua" }
)

foreach ($entry in $deployMap) {
    if (Test-Path -LiteralPath $entry.Destination) {
        Copy-Item -LiteralPath $entry.Destination -Destination $entry.Backup
    }
    Copy-Item -LiteralPath $entry.Source -Destination $entry.Destination -Force
    $sourceHash = (Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) { throw "Hash mismatch: $($entry.Destination)" }
}

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'NowPlayingRouter\.ps1|AppleMusicCollector\.ps1|WiiM-NowPlaying-Bridge\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Start-Sleep -Seconds 5
& 'C:\Program Files\Rainmeter\Rainmeter.exe' !Refresh 'Analog_Floating2'
$backupRoot
```

Keep the printed `$backupRoot`. Roll back with these exact commands, substituting
that path:

```powershell
$liveRoot = 'C:\RainmeterDenon'
$skinRoot = 'C:\Users\timmeh\OneDrive\Documents\Rainmeter\Skins\Analog_Floating2'
$backupRoot = 'C:\RainmeterDenon\Backups\now-playing-diagnostics-YYYYMMDD-HHMMSS'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'NowPlayingRouter\.ps1|AppleMusicCollector\.ps1|WiiM-NowPlaying-Bridge\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Copy-Item "$backupRoot\NowPlaying\NowPlayingRouter.ps1" "$liveRoot\NowPlaying\NowPlayingRouter.ps1" -Force
Copy-Item "$backupRoot\NowPlaying\AppleMusicCollector.ps1" "$liveRoot\NowPlaying\AppleMusicCollector.ps1" -Force
Copy-Item "$backupRoot\NowPlaying\WiiM-NowPlaying-Bridge.ps1" "$liveRoot\NowPlaying\WiiM-NowPlaying-Bridge.ps1" -Force
Copy-Item "$backupRoot\Skin\Includes\DashboardState.inc" "$skinRoot\@Resources\Includes\DashboardState.inc" -Force

if (Test-Path "$backupRoot\NowPlaying\NowPlayingDiagnostic.ps1") {
    Copy-Item "$backupRoot\NowPlaying\NowPlayingDiagnostic.ps1" "$liveRoot\NowPlaying\NowPlayingDiagnostic.ps1" -Force
} else {
    Remove-Item -LiteralPath "$liveRoot\NowPlaying\NowPlayingDiagnostic.ps1" -Force
}
if (Test-Path "$backupRoot\Skin\Scripts\NowPlayingDiagnostic.lua") {
    Copy-Item "$backupRoot\Skin\Scripts\NowPlayingDiagnostic.lua" "$skinRoot\@Resources\Scripts\NowPlayingDiagnostic.lua" -Force
} else {
    Remove-Item -LiteralPath "$skinRoot\@Resources\Scripts\NowPlayingDiagnostic.lua" -Force
}

Start-Sleep -Seconds 5
& 'C:\Program Files\Rainmeter\Rainmeter.exe' !Refresh 'Analog_Floating2'
```
