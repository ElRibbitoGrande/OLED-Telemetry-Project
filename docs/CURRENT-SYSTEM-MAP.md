# Current OLED Telemetry System Map

Status: diagnostic baseline, source audit performed 2026-07-25  
Scope: development repository at `C:\OLED-Telemetry-Project`  
Live installation: `C:\RainmeterDenon` (not inspected or modified)  
Source-of-truth rule: current non-archived source files override backups, generated samples, and historical notes.

## Executive finding

The display is not updated by one end-to-end pipeline. It is a set of independent update domains:

1. Rainmeter's `AudioLevel` plugin drives the two VU needles directly.
2. `denon_status.ps1` publishes consolidated AVR text to `denon_status.txt`.
3. `DecoderCollector.ps1` publishes decoder fields to `decoder_status.txt`; `denon_status.ps1` imports them into the consolidated AVR file.
4. `NowPlayingRouter.ps1` selects either the Apple Music or WiiM collector, which publishes `NowPlaying\now_playing.txt` and artwork.
5. Rainmeter parses the two text files independently with `WebParser`.

This independence makes a partial freeze an expected failure shape. Audio can continue while either text feed is stale; Now Playing can freeze while AVR telemetry continues; and decoder/Audyssey fields can remain stale inside an otherwise changing AVR feed.

The highest-value current suspects are:

- **Now Playing has no effective freshness watchdog.** The manager supervises only that the router process exists. The router supervises only whether its child process has exited. A live but blocked/failing child can leave its panel stale indefinitely.
- **Historical runtime evidence shows competing writers to `now_playing.txt.tmp`.** `apple_music_collector.log` contains many failures such as "file already exists," "being used by another process," and missing `.tmp` paths, continuing through 2026-07-22. This is direct evidence of duplicate/concurrent ownership or a shared temporary-name race.
- **Decoder failure is reported as a healthy heartbeat.** `DecoderCollector.ps1` updates `decoder_heartbeat.txt` in both success and failure paths but leaves the last good `decoder_status.txt` untouched on failure. The manager therefore sees a healthy decoder even while Mode/InputSignal/SampleRate remain stale.
- **The main Denon heartbeat proves loop liveness, not data freshness.** It advances every two seconds even if Telnet is disconnected and all optional XML polls are failing. The manager will not restart that collector.
- **State is deliberately sticky.** The Denon collector imports the previous output at startup and most parsers update only non-empty/valid fields. Failed reads generally preserve prior values without an age marker in the displayed file.
- **Rainmeter's parsers have no explicit stale/error presentation.** A failed file read or full-regex mismatch can retain the last successful WebParser values, while the unrelated AudioLevel measures continue.
- **The production source skin is explicit.** `src\Analog_Floating.ini` is authoritative for this project; `src\Skins\Analog_Floating.ini` is retained as reference material.

No repair or refactor is included in this document.

## Audit scope and evidence quality

README.md and AGENTS.md were read first. All locally present repository files outside Git's internal object database were enumerated and inspected. The audit covered 838 files: 32 PowerShell scripts, 8 command files, 8 VBScript launchers, 2 JavaScript files, 729 Rainmeter INIs, XML/HTML/reference captures, runtime state, logs, images, and backups. Content hashes identified 813 unique file bodies; repetitive Rainmeter variants were checked mechanically for includes, measures, plugins, actions, and external references, with active-looking telemetry skins inspected directly. All 32 PowerShell files passed parser validation.

The requested `docs\chat-archive` directory is not present: `docs` was empty at audit time. No conversation archive could therefore be used. `src\Install Notes 2026-7-18.txt`, archived source versions, generated diagnostic captures, and runtime logs were used only as historical evidence. Current top-level source remains authoritative.

The untracked nested `OLED-Telemetry-Project\` directory contains only its own `.git` metadata and `.gitattributes`; it contains no telemetry implementation.

The repository documents launchers but contains no exported Windows Scheduled Task XML, Startup-folder shortcut, registry Run key, Rainmeter layout/config, or live process/task snapshot. Accordingly, startup mechanisms are separated below into "implemented" and "not proven installed."

## End-to-end topology

```text
Windows startup / manual launch (installation not proven)
  |
  +-- LaunchRainmeter.vbs --10 s--> Rainmeter.exe
  |
  +-- LaunchTelemetryManager.vbs --> TelemetryManager.ps1 (persistent)
                                         |
                                         +--> denon_status.ps1 (persistent)
                                         |      +--> Denon TCP/23
                                         |      +--> Denon HTTPS/10443 type 7, 9, 10
                                         |      +<-- decoder_status.txt
                                         |      +--> denon_status.txt (atomic replace)
                                         |      +--> denon_heartbeat.txt
                                         |
                                         +--> DecoderCollector.ps1 (persistent)
                                         |      +--> Denon HTTPS/10443 type 12
                                         |      +--> decoder_status.txt (atomic replace)
                                         |      +--> decoder_heartbeat.txt
                                         |
                                         +--> NowPlayingRouter.ps1 (persistent)
                                                +<-- denon_status.txt
                                                |
                                                +--> AppleMusicCollector.ps1 (conditional)
                                                |      +--> Windows media sessions
                                                |      +--> iTunes Search/artwork HTTPS
                                                |
                                                +--> WiiM-NowPlaying-Bridge.ps1 (conditional)
                                                       +--> WiiM HTTPS status/meta/art
                                                |
                                                +--> NowPlaying\now_playing.txt
                                                +--> cached artwork JPG

Rainmeter Analog_Floating.ini
  +<-- denon_status.txt through WebParser
  +<-- NowPlaying\now_playing.txt through WebParser
  +<-- Windows output audio through AudioLevel plugin
```

There are no named pipes, sockets between local collectors, databases, registry state objects, memory-mapped files, or IPC queues in current source. Local coordination uses named mutexes, process enumeration, child-process handles, and files.

## Executable inventory

### Current production-intent executables

| File | Expected lifetime | Purpose |
|---|---:|---|
| `src\TelemetryManager.ps1` | Persistent | Single-instance supervisor. Starts/restarts the Denon collector, Now Playing router, and decoder collector; writes manager state. |
| `src\denon_status.ps1` | Persistent | Main AVR collector and state aggregator. Reads Telnet events/queries, slow Denon XML, cached Quick Select names, and decoder state; atomically publishes the AVR status file. |
| `src\DecoderCollector.ps1` | Persistent | Separately polls slow decoder XML (`type=12`) so TLS latency cannot block the main Telnet loop. |
| `src\NowPlaying\NowPlayingRouter.ps1` | Persistent | Reads normalized AVR Source and owns selection/lifecycle of exactly one conditional metadata collector. |
| `src\NowPlaying\AppleMusicCollector.ps1` | Conditional persistent | Reads Windows Global System Media Transport Controls; searches iTunes for matched artwork; writes common Now Playing state. |
| `src\NowPlaying\WiiM-NowPlaying-Bridge.ps1` | Conditional persistent | Polls WiiM player status/metadata/artwork; writes common Now Playing state. |
| `src\LaunchTelemetryManager.vbs` | One-shot | Starts the manager hidden against `C:\RainmeterDenon`. |
| `src\LaunchRainmeter.vbs` | One-shot | Waits 10 seconds, then starts Rainmeter hidden. |
| `src\NowPlaying\LaunchAppleMusicCollector.vbs` | One-shot, legacy/manual | Directly starts Apple collector. This bypasses router ownership and can create competing writers. |
| `src\RestartTelemetry.cmd` | One-shot/manual | Stops all six telemetry PowerShell components, waits 750 ms, and relaunches the manager. |
| `src\StopTelemetry.cmd` | One-shot/manual | Stops all six telemetry PowerShell components. |

### Diagnostic/development executables (not expected to remain running)

| File | Purpose |
|---|---|
| `src\Development\AppleMusicProbe\Test-AppleMusicSession.ps1` | Probes Windows media-session discovery and metadata. |
| `src\Development\CaptureDenonSnapshot.ps1` | Captures selected Denon configuration endpoints for diagnosis. |
| `src\Development\DecoderCollectorTest.ps1` | One-shot decoder endpoint/parser test. |
| `src\Development\DecoderTransportDiagnostic.ps1` | Compares direct curl, cmd-hosted curl, and Invoke-WebRequest transport behavior and writes a report. |
| `src\Development\GeneralServerInterface.js` | Vendor/reference Denon web-interface JavaScript, not a local service. |
| `src\Development\GeneralSettings.js` | Vendor/reference Denon web-interface JavaScript, not a local service. |

### Historical executable copies

Files under `src\Development\Archive\`, `src\Known Good - Atmos DTS Logos\`, `*-before-*`, `*.bak*`, `*-pre-rollback.ps1`, and `denon_status_BeforeQuickSelect.ps1` are rollback/reference snapshots, not current launch targets. They document earlier direct launchers, synchronous curl/HTTP behavior, Rainmeter refresh calls, and earlier manager variants. They must not be inferred to be active merely because executable.

Historical executable groups include:

- 10 dated `denon_status-before-*.ps1` snapshots and current-file backup/source-fix copies.
- `Development\Archive\Pre-1.0_*`: old Denon collector, Apple collector, manager, launchers, stop/restart commands.
- `Development\Archive\BeforeDecoderCollector_*`: pre-decoder manager/Denon and commands.
- `Development\Archive\BeforeFinish_*`: manager, Denon, decoder, launcher, and commands.
- `Development\DecoderCollector-pre-rollback.ps1`, `denon_status-pre-rollback.ps1`, and `denon_status_BeforeQuickSelect.ps1`.
- `Known Good - Atmos DTS Logos\denon_status.ps1` and its Denon/Rainmeter launchers.

## Processes expected to remain running

Steady state should contain:

1. One `Rainmeter.exe`.
2. One PowerShell process for `TelemetryManager.ps1`.
3. One PowerShell process for `denon_status.ps1`.
4. One PowerShell process for `DecoderCollector.ps1`.
5. One PowerShell process for `NowPlayingRouter.ps1`.
6. Zero or one metadata child:
   - Apple collector for `Source=HTPC`.
   - WiiM collector for `Source=LYR+`.
   - Neither for `Source=PS5`, `Source=XBOX`, or any other/unknown source.
7. Transient `curl.exe` child processes:
   - Decoder curl approximately once per 8-second cycle.
   - Quick Select-name curl approximately every 10 seconds, serialized against main collector XML tasks.

Named single-instance mutexes exist for the manager (`Local\RainmeterDenonTelemetryManager`), Denon collector (`Local\RainmeterDenonStatusCollector`), and decoder collector (`Local\RainmeterDenonDecoderCollector`). The router, Apple collector, and WiiM collector have no mutex.

## Startup, scheduled tasks, and Rainmeter triggers

Implemented launch paths:

- `LaunchTelemetryManager.vbs` starts the manager hidden.
- `LaunchRainmeter.vbs` starts Rainmeter after 10 seconds.
- `RestartTelemetry.cmd` manually kills selected collectors and relaunches the manager.
- `StopTelemetry.cmd` manually kills selected collectors.
- The manager launches its three supervised collectors.
- The router launches Apple for `Source=HTPC`, WiiM for `Source=LYR+`, and neither for other sources. Quick Select remains display-only telemetry.
- `LaunchAppleMusicCollector.vbs` is a direct legacy/manual entry point.
- Old `LaunchDenonTelemetry.vbs` files exist only in historical folders.

No Scheduled Task definition or command that creates one is present. No source file proves where either VBS is registered at login. No current Rainmeter skin launches telemetry scripts. Rainmeter's active-looking `OnRefreshAction` only resets meter groups to Stereo visible / Atmos and DTS hidden and redraws.

The repository therefore cannot prove whether live startup is Task Scheduler, Startup-folder shortcuts, manual launch, or some combination. This must be captured from the live machine before any deployment plan.

## Data and shared-state inventory

### Current runtime files

| Path under `C:\RainmeterDenon` | Writer | Reader | Semantics and risk |
|---|---|---|---|
| `denon_status.txt` | Denon collector | Rainmeter; router | Consolidated AVR state, including normalized `Source`, `DisplayMode`, and `LevelSource`. Written only when text changes by temp-and-move. Contains no `Updated` timestamp, so unchanged-valid and frozen are indistinguishable. |
| `denon_status.tmp` | Denon collector | none | Atomic-write staging. Fixed name; mutex normally prevents competing current collectors. |
| `denon_heartbeat.txt` | Denon collector | manager | Loop heartbeat every 2 s; not proof that any source data succeeded. |
| `decoder_status.txt` | decoder collector | Denon collector | Last successful decoder fields plus `Updated`. Preserved on decoder failure. |
| `decoder_status.tmp` | decoder collector | none | Atomic staging. |
| `decoder_heartbeat.txt` | decoder collector | manager | Written after success **and failure**. It is process/cycle liveness only. |
| `decoder_status_error.txt` | decoder collector | operator only | Latest decoder error, overwritten each failure and deleted on success. |
| `decoder_response.xml` | decoder collector | same collector/operator | Latest curl output; removed before each request. Not atomic relative to diagnostics. |
| `decoder_curl_error.txt` | decoder collector | same collector/operator | Latest curl stderr; removed before request. |
| `telemetry_manager.log` | manager | operator | Append-only lifecycle/restart log; no rotation. |
| `telemetry_manager_status.txt` | manager | operator | Process counts/PIDs and file ages; overwritten directly, not atomically. |
| `NowPlaying\now_playing.txt` | router or active metadata child | Rainmeter; manager age check only | Common content state. Fixed `.tmp` staging name is shared by all potential writers. |
| `NowPlaying\now_playing.txt.tmp` | router/Apple/WiiM | none | Shared fixed staging filename. Duplicate writers race on creation/move. |
| `NowPlaying\apple_music_collector.log` | Apple collector | operator | Startup, changed-error, and artwork log; no rotation. |
| `NowPlaying\artwork_a.jpg` / `artwork_b.jpg` | Apple collector | Rainmeter via state path | Alternating artwork targets reduce overwrite contention. |
| `NowPlaying\wiim_artwork.jpg` | WiiM collector | Rainmeter via state path | Last successfully downloaded WiiM art; not deleted when metadata/art fails. |
| `Development\QuickSelectNames.xml` | Denon collector | Denon collector | Persistent last-known-good Quick Select-name cache. |
| `Development\QuickSelectNames.live.tmp` | Quick Select curl | Denon collector | Transient response; removed after completion. |
| `Development\XmlTaskState.log` | Denon collector | operator | HttpClient task diagnostics; unbounded append log. |
| `Development\Audyssey-Raw.xml` | Denon collector | operator | Last successful raw Audyssey response. |
| `Development\Preset-Raw.xml` | Denon collector | operator | Last successful raw speaker-preset response. |

The checked-in `.txt`, `.xml`, `.jpg`, and `.log` files under `src` are samples/copies of live state or diagnostics. Rainmeter and current scripts use absolute `C:\RainmeterDenon` paths, not repository-relative paths.

### Non-runtime reference files

- 729 INIs comprise current telemetry candidates, original VU skins, LED layout permutations by side/resolution/channel/color/delay, backups, and known-good snapshots.
- PNG/JPG files are sample/cached artwork and Rainmeter assets.
- Denon HTML/JavaScript and XML captures are protocol/reference artifacts.
- `fast_status.xml`, `manual_test.xml`, transport reports, and stderr captures are historical diagnostics.
- `.gitignore` intentionally excludes chat archives, logs, transient files, generated telemetry, artwork caches, credentials, and backups.

## Display ownership

The active production skin is `src\Analog_Floating.ini`. `src\Skins\Analog_Floating.ini` remains reference material and is not updated with production presentation routing.

| Display element | Rainmeter measure/meter | Immediate source | Owning component |
|---|---|---|---|
| Left/right VU faces | static image meters | PNG assets | Rainmeter skin |
| Left/right needles and shadows | `MeasureDisplayRMS_L/R` | Windows output RMS gated by `LevelSource` | Rainmeter `AudioLevel` plugin plus Denon presentation state |
| Center volume | `MeasureVolumeRelative` -> Calc +80 | `denon_status.txt` Volume | Denon collector, Telnet `MV` |
| Source | `MeasureSource` | `denon_status.txt` Source | Denon collector, normalized from AVR `SI` and XML source |
| Quick Select label | `MeasureQuickSelectName` | consolidated status | Denon collector, Telnet `MSQUICK` plus type=7/cache names |
| Listening mode | `MeasureMode` | consolidated status | Decoder file takes precedence every 750 ms; Telnet `MS` can update between imports |
| Audio/input format | `MeasureInputSignal` | consolidated status | Decoder collector type=12 via Denon importer |
| Sample rate | `MeasureSampleRate` | consolidated status | Decoder collector |
| MultEQ | `MeasureMultEQ` | consolidated status | Denon collector type=9 Audyssey XML |
| Dynamic EQ | `MeasureDynamicEQ` | consolidated status | Denon collector type=9 Audyssey XML |
| RLO, Dynamic Volume, Speaker Preset | parsed; some not displayed in this skin revision | consolidated status | Denon collector type=9/type=10 |
| VU/Atmos/DTS/Xbox/PS5 presentation | mutually exclusive meter groups | `DisplayMode` | Denon presentation decision plus Rainmeter WebParser actions |
| Meter level source | gated RMS calculation | `LevelSource` | `PC_AUDIO` enables AudioLevel; `NONE` rests needles; `ANALOG_ADC` is reserved for future integration |
| Now Playing visibility | `MeasureMusicActive` | `now_playing.txt` Active | Active metadata collector/router; Rainmeter show/hide action |
| Service, title, artist, album | music WebParser children | `now_playing.txt` | Apple or WiiM collector |
| Artwork | `MeasureMusicArtwork` path | cached JPG | Apple or WiiM collector |
| Time/duration/progress | music WebParser children | `now_playing.txt` | Apple or WiiM collector |
| Static labels/panels | Rainmeter meters | INI | Rainmeter |

For `Source=LYR+`, WiiM supplies content metadata only and the analog LYR+ path has no level telemetry. The current `LevelSource=NONE` intentionally rests the existing needles. A future high-impedance RCA sensing PCB and ADC collector should integrate by supplying `LevelSource=ANALOG_ADC`; it must not change source-based metadata routing or the display layout.

The former channel placeholder in the active skin is used for the Quick Select friendly name. Quick Select remains display-only telemetry and does not control metadata, presentation, artwork, or level routing.

## Network and external-source calls

### Denon AVR-X3700H (`192.168.0.128`)

| Transport | Request | Cadence/timeout | Consumer |
|---|---|---|---|
| TCP port 23 | Persistent Telnet; initial `MV?`, `SI?`, `MS?`, `MSQUICK ?` | Connect call has no explicit timeout; reconnect delay 1 s | Volume, source, listening mode, Quick Select |
| TCP port 23 | `MV?` | 100 ms | Volume |
| TCP port 23 | `MSQUICK ?` | 1 s | Quick Select |
| HTTPS 10443 | `/ajax/general/get_config?type=12&_={timestamp}` | Decoder cycle target 8 s; curl connect 5 s/max 12 s | Mode, input signal, sample rate |
| HTTPS 10443 | `/ajax/general/get_config?type=7&_={timestamp}` | 10 s; curl max 15 s | Quick Select friendly names |
| HTTPS 10443 | `/ajax/audio/get_config?type=9&_={timestamp}` | requested on 5 s schedule; HttpClient timeout 10 s | MultEQ, Dynamic EQ, RLO, Dynamic Volume |
| HTTPS 10443 | `/ajax/globals/get_config?type=10&_={timestamp}` | requested on 10 s schedule; HttpClient timeout 10 s | Speaker preset |

Type 7 is serialized ahead of type 9/10 inside the main collector. The separate decoder collector is not coordinated with that serialization, so type 12 can overlap the main collector's HTTPS calls despite the historical note that the AVR HTTPS service is effectively single-lane.

TLS certificate bypass is scoped differently:

- Denon HttpClient accepts the AVR certificate on its handler.
- Denon curl calls use `-k`.
- WiiM's Windows PowerShell 5 path installs a process-wide `ServicePointManager.CertificatePolicy` that trusts all certificates within that WiiM process. It does not globally change the machine, but is broader than the single WiiM endpoint.

### WiiM (`192.168.0.249`)

| Request | Cadence/timeout |
|---|---|
| `https://.../httpapi.asp?command=getPlayerStatus` | every 2 s, sequential, 5 s timeout |
| `https://.../httpapi.asp?command=getMetaInfo` | every 2 s after status, 5 s timeout |
| Metadata-provided `albumArtURI` | on track change/missing cache, 10 s timeout |

Worst-case failed cycle is roughly 10 seconds before sleep (or 20 with artwork), because requests are sequential. No separate cancellation token or retry within a cycle exists.

### Apple/Windows

| Source | Request | Timeout |
|---|---|---|
| Windows GSMTC media sessions | manager request, session enumeration, media properties, timeline | `Await-WinRT` calls `.Wait()` with no timeout |
| iTunes Search API | `https://itunes.apple.com/search?...` | 10 s |
| Selected iTunes artwork URL | HTTPS download | 15 s |

No current Plex endpoint, token, process query, or file integration exists. Plex is mentioned only in README's broad component description. If Plex playback appears, it can only be exposed indirectly through Windows media sessions in current source.

## Timing, retries, exception handling, watchdogs, and restart behavior

### Manager

- Main loop: 3 s plus startup sleeps.
- Denon stale threshold: 12 s heartbeat age; stops collector and restarts next loop.
- Decoder stale threshold: 30 s heartbeat age; same behavior.
- Router: process-count supervision only; no heartbeat restart.
- Metadata child: not supervised by manager; router checks child `HasExited`.
- Duplicate manager prevented by mutex.
- Duplicate Denon/router/decoder detection: manager restarts cleanly when process enumeration finds more than one. Router lacks mutex but manager checks its count.
- `Find-Collector` relies on `powershell.exe` and regexes over command lines; `pwsh.exe`, renamed scripts, or inaccessible CIM data are invisible.
- `$ErrorActionPreference='Stop'` and no outer catch around the loop. An error in logging, state writing, CIM, or startup logic can terminate the manager. `finally` logs shutdown, but that log write can itself fail.
- No external watchdog supervises the manager in repository source.

### Denon collector

- Main loop: 20 ms.
- Telnet reconnect: 1 s.
- Telnet writes catch and discard exceptions without immediately closing the connection.
- TCP `Connect()` has no explicit timeout/cancellation; a long OS-level connect can block the loop and heartbeat, eventually causing manager termination if the manager is alive.
- Socket reads occur only when `DataAvailable`; `ReadLine()` can still wait for a terminator after partial data, potentially blocking until more bytes/closure.
- Decoder file import: 750 ms; all errors swallowed.
- HttpClient: lazy shared client, 10 s timeout, tasks polled asynchronously.
- Type 7 curl: 15 s maximum; start/parse errors swallowed.
- XML task pending state logged every 2 s; fault/cancel/apply errors logged.
- Type 9 request schedule: 5 s; type 10: 10 s; type 7: 10 s. Only one task per type is allowed. Type 9 and type 10 may overlap each other; type 7 will not start while either is in flight.
- Quick Select-name cache is loaded on startup and retained after live failures.
- Output written atomically only on content change.
- Heartbeat written every 2 s regardless of input success.
- Main loop lacks a catch around all operations. An unexpected terminating file-write/task/property error can kill the process; manager should restart it when heartbeat ages.

### Decoder collector

- Target cycle: 8 s including request; minimum post-request sleep 250 ms.
- curl connect timeout 5 s, total timeout 12 s.
- Every cycle is caught.
- Success atomically updates status and heartbeat, and deletes error file.
- Failure updates error and heartbeat but deliberately preserves prior status.
- Manager therefore handles a hung/dead process, but not repeated failed polls.

### Now Playing router

- Polls `denon_status.txt` every 2 s.
- Read failures are warnings and return empty state, which selects `None` and clears/hides Now Playing.
- Restarts a child only if `HasExited`; no output age, responsiveness, or success test.
- Stops all matching Apple and WiiM PowerShell processes on startup/mode change.
- Process matching uses only leaf script filename; it can affect development/manual copies with the same leaf.
- No mutex. No persistent log when launched hidden; `Write-Host`/warnings are normally lost.
- Its `finally` stops the current metadata collectors, but force termination or manager kill may bypass orderly cleanup.

### Apple collector

- Default poll interval is defined in script parameters (current loop sleeps by milliseconds).
- Windows async calls use blocking `.Wait()` with no timeout. A stuck WinRT operation can freeze the child permanently while router sees it alive.
- Poll errors are caught; inactive/blank state is then written.
- Repeated identical errors are logged once until success/different error.
- Artwork errors are caught without failing metadata publication.
- Fixed `.tmp` status filename can collide with another writer.
- No mutex, heartbeat, or watchdog.
- Stable artist/album intentionally retains last non-empty values until title changes.

### WiiM bridge

- Polls every 2 s after work completes.
- Status/meta requests each timeout at 5 s; art at 10 s.
- Whole cycle errors publish inactive/blank state.
- Artwork download errors do not fail metadata; existing cached art may remain and be marked available if file exists.
- Fixed `.tmp` status and artwork names can collide with duplicate writers.
- No mutex, heartbeat, log file, or watchdog beyond child exit detection.

### Rainmeter

- Skin update interval: 32 ms.
- Both file WebParser parents use `UpdateRate=1` (one skin update).
- AudioLevel is independent of file parsing.
- No file-age measure, producer heartbeat measure, parse-error meter, or automatic refresh/recovery action exists.
- The skin's sole refresh action resets visual groups and redraws.

## Every stale-output preservation path

1. **Denon startup import:** every prior status field is loaded from `denon_status.txt`, then retained until a valid update arrives.
2. **Telnet disconnect/failure:** state is not cleared. Heartbeat continues while reconnect attempts occur.
3. **Ignored invalid Telnet values:** invalid volume, `MSQUICK 0`, blank lines, and unrecognized/missing replies preserve prior fields.
4. **Silent Telnet write failure:** `MV?`/`MSQUICK ?` write errors are swallowed, so the connected flag can remain misleading and old values persist.
5. **Decoder file absent/unreadable/malformed:** import returns or swallows error; previous Mode/InputSignal/SampleRate remain.
6. **Decoder poll failure:** output file remains last successful; heartbeat still advances.
7. **Partial decoder XML:** only non-empty recognized fields replace state; others remain old.
8. **Audyssey request fault, cancel, bad XML, or missing nodes:** last MultEQ/DynamicEQ/RLO/DynamicVolume values remain.
9. **Preset request fault/bad XML/missing node:** last SpeakerPreset remains.
10. **Quick Select-name HTTP failure/bad XML:** cached names remain. Cache write failures are swallowed.
11. **Quick Select `0`:** deliberately ignored, preserving previous Quick Select display telemetry; it does not control metadata routing or presentation.
12. **Visual-mode stabilization:** a new mode must be observed twice; blank/unstable detection retains prior visual mode.
13. **Status write-on-change:** no timestamp changes when state is unchanged, so freshness cannot be inferred from file mtime during legitimately steady state.
14. **Status atomic-move failure:** terminating error can leave previous output in place until manager restart; restart imports it again.
15. **Router Denon read failure:** it chooses `None` and attempts a blank file; if that write fails, old Now Playing state remains.
16. **Metadata child alive but hung:** router takes no action; last Now Playing file remains forever.
17. **Competing Now Playing writers:** fixed `.tmp` races can prevent publication; the existing final file remains.
18. **Apple stable metadata:** artist/album are intentionally sticky until title changes.
19. **Apple artwork lookup failure:** current artwork is set blank for a new key, but an existing image file remains on disk; display behavior depends on the published path.
20. **WiiM artwork failure:** prior `wiim_artwork.jpg` can be treated as available because existence, not track identity/success, decides availability.
21. **Rainmeter WebParser read/regex failure:** child measures can keep their last successful values; no explicit invalidation is configured.
22. **Rainmeter group state:** if `MeasureMusicActive` stops changing because parsing freezes, the Now Playing group remains in its last shown/hidden state.
23. **Manager death:** all children may continue independently with no repository-defined mechanism to restart the manager; later individual hangs will not recover.
24. **Process-discovery dependence:** stop/restart and supervision depend on `powershell.exe` command-line matching; inaccessible CIM data or a different PowerShell host can evade detection.

## Conditions producing a partial rather than total freeze

| Failure condition | Frozen/stale region | Region likely still moving |
|---|---|---|
| Denon collector dead/hung and manager absent/dead | AVR text and mode-dependent visuals | VU needles; possibly Now Playing child |
| Telnet disconnected while Denon loop alive | Volume/source/Quick Select/listening events | VU; Now Playing; slow XML-derived fields may still change |
| Decoder endpoint repeatedly fails | Mode, input format, sample rate | Volume/source/Quick Select, VU, Now Playing, Audyssey |
| Audyssey task repeatedly fails | MultEQ/Dynamic EQ/RLO/Dynamic Volume | Volume/source/mode, VU, Now Playing |
| Quick Select name type=7 fails | friendly label | raw Quick Select/source/volume/mode, VU |
| Now Playing child hangs | title/art/time/progress and group state | all AVR fields and VU |
| Duplicate Now Playing writers race | intermittent or persistent Now Playing publication | AVR and VU |
| Rainmeter parser for one file fails | all elements sourced from that file | other WebParser file and AudioLevel |
| AudioLevel capture/plugin failure | needles only | text telemetry and Now Playing |
| Rainmeter skin/group action failure | logos or Now Playing visibility only | underlying text files and other meters |
| Fixed cached artwork is stale | artwork only | title/time/progress and AVR/VU |
| Mode stabilization/ignored invalid response | mode/logo only | volume/source and unrelated panels |

An especially plausible observed sequence is: a direct/stray Apple launcher or an incompletely stopped router leaves multiple metadata writers; both use `now_playing.txt.tmp`; writes intermittently fail; the router sees its own child alive and the manager sees the router alive; no watchdog reacts; the final file and Rainmeter panel retain their last values while AVR text and VU continue.

## Historical evidence

Current checked-in runtime copies show:

- `telemetry_manager.log`: 38 manager starts, 120 collector starts, and only 7 orderly manager stops in the summarized lifecycle categories. No Denon/decoder stale-heartbeat restart was found in that log copy.
- `apple_music_collector.log`: repeated fixed-temp-file collisions and missing-temp failures, including "Cannot create a file when that file already exists," "being used by another process," and "does not exist." These span early development and continue into 2026-07-22, so they are not merely a single startup incident.
- The Apple log also records a blocking WinRT `.Wait()` aggregate failure and historical Windows runtime availability/startup issues.
- `Install Notes 2026-7-18.txt` records the architectural lesson that Denon Telnet is reliable, HTTPS is fragile/single-lane, concurrent requests can destabilize network services, and optional metadata must not delay live telemetry.
- Transport captures confirm unusually slow TLS behavior on Denon HTTPS 10443 and motivated the separate decoder collector.

These files establish plausible failure mechanisms, but because they are repository copies rather than a synchronized live incident bundle, they do not prove which failure occurred during the most recent observed freeze.

## Proposed logging plan for the next partial freeze

The plan should be implemented in a later, separately reviewed change. It should add observability without altering collector ownership, polling cadence, or display behavior.

### 1. Use one correlation clock and structured records

Write newline-delimited JSON with:

- UTC timestamp with milliseconds and local timestamp/offset.
- component, PID, process start time, build/script hash, and session ID.
- cycle/operation ID.
- event name, success/failure, elapsed milliseconds, exception type/message.
- source observation timestamp and publish timestamp.
- destination path, bytes, content hash, and monotonic sequence number.

Avoid track names, artwork URLs with tokens, credentials, private configuration, or full raw payloads in routine logs.

### 2. Separate liveness, source success, and publication freshness

For every component record three clocks:

- `loop_alive_at`: process completed another loop.
- `source_success_at`: its upstream source returned and parsed successfully.
- `publish_success_at`: final output was atomically replaced successfully.

This directly fixes the current ambiguity where decoder and Denon heartbeats mean only loop liveness.

### 3. Component event coverage

**Manager**

- Each discovery snapshot: PID/count/command-line identity for all five script types.
- Start/stop reason, process exit code when available, heartbeat/source/publish ages.
- Manager-loop duration and any exception before exit.
- Router and metadata output age watchdog observations, even before enabling restart behavior.

**Denon**

- Telnet connect start/success/failure/duration; disconnect reason.
- Last received line time by command family (`MV`, `SI`, `MS`, `MSQUICK`) and query-write failures.
- Per-field provenance and last-success age.
- XML task start/complete/timeout/fault/parse/apply duration by type.
- HTTPS concurrency gauge across both Denon processes if feasible via a shared diagnostic lock/counter.
- Status publish sequence, hash, changed field names, elapsed time, and write/move errors.

**Decoder**

- curl start/end, exit code, duration, response bytes, parse result, and individual field presence.
- Separate success heartbeat from loop heartbeat.
- On failure, log age/hash of the preserved decoder payload.

**Router**

- Input file read result, age/hash/sequence, selected mode, child PID/start time.
- Child exit, mode transition, stop result, and output freshness age.
- Persist these events to a real router log rather than hidden console output.

**Apple/WiiM**

- Poll start/end and stage durations.
- WinRT await operation names and elapsed time; a periodic "operation still pending" marker.
- HTTP endpoint category, status/exit, timeout, response bytes (not sensitive URL query data).
- Status/art temp-file create/write/move result, writer PID, target hash/sequence.
- Detect and log another writer's PID/session marker before touching the shared temp path.

**Rainmeter**

- Add diagnostic-only file age/sequence/hash measures for both source files.
- Record WebParser parent success/error and parsed sequence.
- Expose a small optional diagnostic overlay or a separate diagnostic skin showing:
  - producer success age,
  - publish age,
  - Rainmeter consumed sequence,
  - PID/session,
  - parse status.
- Capture Rainmeter's own log around an incident.

### 4. Bounded storage

- One log per component per session/day.
- Rotate by size (for example 5–10 MB) and retain a small bounded set.
- Write to `C:\RainmeterDenon\diagnostics` in live use; exclude it from commits.
- Flush error, lifecycle, source-success, and publish records immediately.
- Do not log every 20 ms loop or every 100 ms volume query. Aggregate high-rate metrics into 5-second summaries and log state changes.

### 5. Incident snapshot

Provide a read-only `Capture-PartialFreeze.ps1` diagnostic command in a later change. It should copy, without restarting anything:

- UTC/local capture time.
- Process list with PID, start time, command line, parent PID, CPU, handles, threads, and responding/exited state where available.
- Manager status and all heartbeat/source/publish ages.
- Current and temporary telemetry files with timestamps, sizes, hashes, and safe contents.
- Tail of each bounded component log and Rainmeter log.
- Active TCP connections to Denon/WiiM and transient curl processes.
- Scheduled task definitions, Startup-folder entries, and relevant Run keys.
- Rainmeter active skin/layout/config identity and source-file paths.
- Optional screenshot of the frozen display.

Package the snapshot in a timestamped diagnostics folder, not Git. Never include credentials or unrelated system data.

### 6. Freeze classification rule

At capture time classify each display domain independently:

| Domain | Healthy evidence |
|---|---|
| VU | AudioLevel samples/needles changing |
| AVR Telnet | recent successful receive for relevant command and newer published sequence |
| Decoder | recent type=12 success and decoder sequence consumed by Denon |
| Audyssey/preset | recent endpoint success for each field group |
| Now Playing | recent child source success, publication, and Rainmeter-consumed sequence |
| Presentation | Rainmeter parse success and meter update/redraw after latest producer sequence |

The first broken edge identifies whether the incident is upstream acquisition, parsing, publication, supervision, or Rainmeter consumption.

## Recommended diagnostic order (no implementation yet)

1. Capture the live startup mechanisms and active Rainmeter skin identity; repository source cannot establish them.
2. At the next freeze, run the incident snapshot before any restart.
3. First compare producer success/publish/consume sequences for the frozen region.
4. Check for duplicate router/Apple/WiiM processes and `.tmp` ownership failures.
5. Check decoder source-success age rather than its current heartbeat.
6. Check Denon Telnet last-receive ages independently from main loop heartbeat.
7. Only after evidence identifies the failed edge should a narrowly scoped repair be proposed.

## Deployment and rollback

No PowerShell or runtime behavior change is proposed or deployed by this report. The only new development artifact is this Markdown file. No commit has been created.

For a future logging-only change, the exact deployment and rollback steps must be specified after the changed scripts and their callers are known. At minimum deployment would require validated copies from this repository to the corresponding `C:\RainmeterDenon` paths, controlled telemetry restart, PID/heartbeat verification, and Rainmeter verification. Rollback must restore the pre-change script copies/commit and restart the same process set. Nothing should be copied to the live installation automatically.
