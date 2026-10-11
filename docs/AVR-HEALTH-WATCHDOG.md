# AVR telemetry health and recovery

The reported coherent obsolete LYR+/STEREO/volume state was corrected by an
ordinary AVR standby cycle after Windows reboots did not help. That supports
an AVR control-service/session hypothesis, but does not prove the incident's
root cause. No synchronized incident capture exists. Code inspection identified
additional Windows-side paths: imported startup state, liveness-only heartbeats,
missing periodic input reconciliation, a blocking line reader on a CR protocol,
and decoder files preserved indefinitely after failures.

## Architecture and authority

`denon_status.ps1` remains the sole canonical-state writer. It starts empty,
actively queries input/power every second, preserves existing volume/mode/channel
polling, reads available socket bytes with bounded CR framing, and reconnects
when critical replies expire. Connect timeout is 1.5 seconds, write timeout one
second; partial frames cannot block reading. Last-known values are retained in
the observation report, not imported as current state after restart. Decoder
format/sample rate expires after 45 seconds. TCP MS responses remain the only
listening-mode authority; MSQUICK responses cannot overwrite it.

`AvrWatchdog.ps1` runs separately, supervised by TelemetryManager. It opens one
short-lived TCP connection every 45 seconds, sends PW?, SI?, MV?, MS? with 60 ms
spacing, then closes it. Startup verifies immediately. The entire check has a
2.5-second budget (connect capped at 1.5 seconds). CV? and MSQUICK ? are included
approximately every 10 minutes; a completed channel transaction also requests
canonical reconciliation and re-scheduling of the existing optional XML polls.
No extra HTTPS polling lane is introduced. The real AVR accepted the independent
connection alongside its existing collector and returned matching critical state.

Command semantics follow [Denon's published protocol](https://assets.denon.com/DocumentMaster/DE/IP_Protocol_AVR-Xx100.pdf).
Compatibility of the specific model was established through live read-only
queries. Healthy verification adds four commands per 45 seconds plus two per
10 minutes. Existing collector cadence is otherwise preserved; input/power adds
two commands per second. Diagnostics record measured verification duration.

Heartbeats, process existence and file mtime are not correctness evidence.
Collector observations contain per-field successful receive times even for
unchanged values. Critical fields expire at 15 seconds; publication expires at
8 seconds. Independent successful verification expires at 120 seconds. Those
thresholds allow margin over measured subsecond TCP replies and two-second
publication. Future timestamps are invalid. Active failures retry at 15-second
intervals, rather than generating many competing connections.

## Recovery and warning criteria

Recovery is restricted to the affected domain: read-only reconciliation,
collector reconnect, then collector termination so its manager can replace it.
Stages are separated by at least 30 seconds; freshness and canonical agreement
are checked every two seconds before escalation. At most one restart occurs
within a fault episode, with a 10-minute restart cooldown across episodes.
The collector also has its own freshness reconnect. An independent snapshot
mismatch persists until subsequent verification resolves it.

Decoder success age is checked separately from its heartbeat. A stale/invalid
decoder sample permits one targeted decoder restart per outage after a 30-second
grace, with a 10-minute cooldown across outages. Continued HTTPS failure is logged
and reported, never used alone to blame the AVR TCP control service.

Rainmeter acknowledges health session, source/mode/volume measures and its Lua
update time. A missing/stalled acknowledgment or mismatched consumed values
permits a targeted measure/meter update, then a targeted AF2 refresh after a
120-second cooldown. Two attempts are allowed until acknowledged recovery.
Refresh All is deliberately unnecessary for this implementation. Acknowledgment
verifies software measure progression, not pixels or a physical display. A frozen
parser containing unchanged correct values is indistinguishable until a state
transition. No automatic power, input, volume, mode or configuration commands exist.

RESET AVR requires all of:

- At least six failed independent control verifications over at least 180 seconds.
- Critical collector observations are also stale.
- Reconciliation, reconnect and a collector restart have been attempted without recovery.
- A previous successful independent verification exists. Its historical baseline
  survives watchdog restart, but never makes historical values trusted current state.
- Last independently verified power was ON; previously verified standby or unknown
  power prevents ambiguous power-save outages from recommending reset.
- A fresh response from the separate HEOS device-description service identifies
  the exact Denon AVR-X3700H model and matches a previously observed device-UDN
  fingerprint at the configured address. The fingerprint is pinned only while
  critical control verification succeeds; an unknown/replaced device cannot
  enable the warning. One bounded identity request initializes this baseline.

ICMP success, open TCP ports, a missing collector, wrong address, local/LAN outage,
and a single timeout are insufficient. If HEOS identity is unavailable, the cause
remains ambiguous and no reset recommendation appears. Fresh standby replies
suppress reset and recovery escalation. Startup with no historical successful
verification also remains conservative. A new successful critical query removes
the warning automatically. Identity supports an AVR control-service inference;
it does not prove hardware failure. Fresh network replies could themselves describe
obsolete internal AVR state; no available sensor can conclusively detect that case.

Failed checks record local interface status and bounded (300 ms) AVR/gateway ICMP
observations, alongside fresh TCP connection and exact-model HEOS results.
Inference distinguishes absent local interfaces, a responding LAN peer with an
unverified AVR address, a responding address with unverified control, and an
identified AVR on a separate service. Unanswered ICMP cannot distinguish a LAN
failure from filtering or an AVR/address problem; that remains explicitly ambiguous.
These probes never establish correctness and never enable RESET AVR by themselves.

## Presentation

`AvrHealthPresentation.lua` reads a separate health file directly once per second,
independent of source WebParser and logo selection. Health expires after 10
seconds, suppressing old warning/trust decisions if the watchdog stops.
Healthy operation displays normal values/logos. Temporary recovery emits no
warning; once observations become untrusted, AVR values, active speaker overlays,
logos and needles are quietly hidden rather than inventing state. Existing face
art, labels and independently acquired metadata are retained. RESET AVR uses
native Rainmeter shapes/text in the normal logo area, including ordinary
off / HDMI-HDR reset / on instructions. No raster dependency is needed.

## Files, callers and failure isolation

| Component | Callers | Runtime reads/writes |
|---|---|---|
| Denon collector | TelemetryManager; existing manual launch | Existing canonical/decoder/cache/XML files; writes `avr_collector_observation.json`; reads `avr_recovery_request.json` |
| Watchdog | TelemetryManager | Reads observation, canonical and presentation acknowledgment; writes `avr_health.json`, `avr_health_display.txt`, recovery request and bounded `Logs/AvrWatchdog.jsonl` |
| AvrHealth helper | Collector, watchdog, diagnostic tests | Bounded atomic file helpers; pure formatting extracted from collector AST; fresh network queries |
| Presentation Lua | AF2 skin Script measure | Reads health display; writes `avr_presentation_ack.txt`; controls only AF2 AVR presentation |
| Manager/process control | Existing startup/manual launchers | Adds watchdog supervision/stop identity; existing components keep independent lifecycle |

Report and log data are runtime output and excluded from Git. Log rotation retains
one archive at 1 MiB per file. Healthy summaries occur every five minutes and
independent check results every 45 seconds. Logging errors do not stop supervision.
JSON/text publication retries three times with 50 ms backoff; collector/watchdog
failures remain in separate processes. Manager gives watchdog 60 seconds of startup
grace, then restarts stale publication. The existing manager itself has no newly
introduced external supervisor; its complete death remains an operational limit.

Read-only report:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OLED-Telemetry-Project\diagnostics\Get-AvrHealth.ps1
```

Report includes overall trust, critical field times/values, connectivity/query
validity, independent/comprehensive verification times, canonical mismatches,
presentation acknowledgment, escalation/actions, last successful recovery and
warning inference. Never equate a stale report with a current healthy watchdog.
`Overall=Healthy` means critical AVR control and canonical values agree;
`OptionalHealth` and `DecoderFresh` separately describe decoder availability.

## Automated validation

Run under Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File diagnostics\Test-AvrWatchdog.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File diagnostics\Test-AvrWatchdogEscalation.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File diagnostics\Test-ListeningModeAuthority.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File diagnostics\Test-TelemetryManagerLifecycle.ps1
```

The localhost fake AVR sends fragmented CR replies and records any non-allowlisted
command. Tests cover healthy unchanged state, alive-but-silent and absent/stale
collector, stale canonical/source values, dropped connection, bounded timeouts,
restored connectivity, actual collector startup reconciliation and reconnect.
Virtual-clock tests execute the real watchdog loop with injected transport for
prolonged control failure, LAN/identity failure, healthy collector with failed
probe, normal standby, warning appearance/clearing and bounded escalation.
Physical AVR failure is never injected. Listening-mode/channel transaction and
manager/hotkey lifecycle regression tests preserve earlier repairs. No physical
Lyr+ switching is required. Existing artwork, VU envelope/HKLM, pixel shift and
hotkey implementations are outside the deployment file list.

## Deployment and rollback

The task explicitly authorizes production deployment. Only seven explicit files
are copied. Before any production mutation, Deploy-AvrWatchdog creates a timestamped
`C:\RainmeterDenon\Backups\AvrWatchdog-*` folder and a manifest, verifies original
hashes, and records which new files were originally absent. It stops only manager,
watchdog and Denon collector. Other collectors/hotkeys remain running. It copies
validated files, checks deployed hashes, restarts the manager and refreshes only
AF2. Copy/start errors invoke rollback automatically. Runtime trust resets on the
next watchdog session; subsequent independent queries must validate it anew.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OLED-Telemetry-Project\diagnostics\Deploy-AvrWatchdog.ps1 -Action Deploy
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OLED-Telemetry-Project\diagnostics\Deploy-AvrWatchdog.ps1 -Action Rollback -BackupPath C:\RainmeterDenon\Backups\AvrWatchdog-YYYYMMDD-HHMMSS
```

Rollback verifies the complete manifest, refuses targets outside the explicit
deployment list, restores prior files/removes newly added code files, then
restarts the prior manager and refreshes AF2. Retained diagnostic state is inert
under the prior skin/manager and preserves incident evidence. No recursive
deletion, settings changes or blanket collector shutdown is used.

## Production validation on 2026-10-11

Deployment backups:

- `C:\RainmeterDenon\Backups\AvrWatchdog-20261011-154026` restores the original production state.
- `C:\RainmeterDenon\Backups\AvrWatchdog-20261011-154343` restores the first watchdog deployment.

All existing-file backup hashes were verified. The first startup comprehensive
check took 1,223 ms; a subsequent critical verification took 262 ms. Both independently
reported HTPC, DOLBY SURROUND, power ON and relative volume -19.5 dB (absolute 60.5).
The Rainmeter Lua acknowledgment matched the watchdog session and consumed values.
Critical trust, channel freshness and presentation progression were healthy;
RESET AVR remained false. This validates software consumption, not physical pixels.

`Test-AvrRuntime.ps1 -InjectCollectorFailure` terminated only the exact production
Denon collector, verified its automatic single replacement and fresh recovery,
and confirmed unchanged metadata/Box1/router/hotkey PIDs. Exactly one manager,
watchdog, Denon, decoder, Box1, router and hotkey listener remained. The collector,
prolonged-failure, listening-mode/channel and manager lifecycle automated suites
passed. Fixture mutexes differ from production so tests can run while deployed.

The pre-existing decoder HTTPS endpoint continues to time out after one targeted
restart. Its last successful sample was old. Decoder/optional fields that cannot
be freshly acquired remain unavailable; no known-old format is shown as current.
That service outage does not invalidate working TCP input/volume/listening-mode
observations and does not alone satisfy RESET AVR criteria. No AVR settings or
power were changed, and no physical Lyr+ test was needed. The physical incident's
root cause and front-panel consistency under an internal AVR cache failure remain
unproven; diagnostics retain that distinction.

Live regression/identity command (read-only by default; explicit switch injects
the targeted collector termination already described):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OLED-Telemetry-Project\diagnostics\Test-AvrRuntime.ps1
```

Exact rollback to the original production installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OLED-Telemetry-Project\diagnostics\Deploy-AvrWatchdog.ps1 -Action Rollback -BackupPath C:\RainmeterDenon\Backups\AvrWatchdog-20261011-154026
```
