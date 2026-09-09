# Listening-mode authority investigation — 2026-09-08

Baseline: `fdbd1ee743e246b5f8db18d5b8fe0fa42ba24d56`, branch `dashboard-3`.

## Evidence and cause

The deployed and repository Denon collectors matched before the change.
`decoder_status.txt` retained a September 2 Dolby Surround result while
DecoderCollector continued reporting connection timeouts. Its heartbeat stayed
fresh because its error path updates the heartbeat too.

The 60-second reproduction capture recorded 35 `MSMCH STEREO` responses and no
other listening-mode response. Published state nevertheless alternated between
`MCH STEREO` and `DOLBY SURROUND`. `Apply-DecoderStatusFile` overwrote TCP mode
every 750 ms without checking whether the decoder file had changed or was fresh.
The decoder value came from XML SoundMode, not an inference from PCM or source.

Initial diagnostic MS?/CV? queries were broadcast by the receiver to other
connections. Extra CV? traffic amplified partial channel publications, so that
capture cannot establish the original speaker-churn cause. A subsequent
30-second passive capture showed stable topology. A later passive mode-change
capture reproduced partial publications in production and in Rainmeter: entire
front/surround groups disappeared while complete raw lists still included them.
The collector cleared pending channel rows on each query timer, even when an
earlier response was still being consumed. CVEND then committed only its tail.
The retained capture tool
never sends extra CV? queries; `-Passive` sends no queries at all.

## Authority path and repair

TCP MS replies -> Process-DenonLine -> state.Mode -> denon_status.txt ->
DashboardDenonStateFile -> DashboardRawListeningMode -> DashboardListeningMode
-> AF2ListeningModeValue. There is no registry transport in this path.
DashboardState.lua consumes mode for logo selection; it does not assign mode.
Source normalization does not set the listening mode.

Only TCP replies now update the live mode. MS? is queried once per second so a
lost unsolicited event is recoverable. MCH STEREO is expanded to MULTICHANNEL
STEREO. Decoder imports retain separate InputSignal and SampleRate telemetry.
The unused Apply-FastXml function also no longer assigns mode.
The existing startup import still preserves the previous display until a reply
arrives. No new freshness claim is made for cached startup or decoder data.

CV rows and CVEND populate Active* fields, which flow through the same state
file into DashboardActive* measures and AF2 speaker visibility controllers.
Collection now starts/reset at the observed CVFL response boundary, commits at
CVEND, and discards pending state on disconnect. Sending CV? no longer clears
an in-progress response. Orphan tails are ignored. No speaker debounce or skin
redraw change has been made. This framing is validated for this AVR's captured
responses; it is not asserted as a universal protocol for other receiver models.

## Callers, I/O, and failure review

TelemetryManager starts and supervises denon_status.ps1. The main loop calls
Process-DenonLine and Apply-DecoderStatusFile; Apply-FastXml has no live caller.
The changed formatter is called by Process-DenonLine. The collector reads its
previous status, decoder_status.txt, and the existing Quick Select cache; writes
denon_status.tmp/txt, denon_heartbeat.txt, and existing XML diagnostic/cache files.
No output schema or additional production file was introduced.

Decoder failures remain isolated in the separate collector and can no longer
overwrite live mode. The repair uses the existing TCP write/catch and reconnect
paths, introduces no synchronous HTTP request, sleep, or retry loop. Existing
TCP Connect/ReadLine behavior remains a limitation: this change does not claim
to fix all possible network stalls. Manager supervision and unrelated collectors
remain unchanged. Decoder connection failures predate the repair and persist.

## Validation

PowerShell parser validation and Test-ListeningModeAuthority.ps1 pass. Tests
replay Stereo -> Dolby Surround -> Multichannel Stereo -> Stereo on both HTPC
and LYR+, interleaving stale decoder imports and Quick Select replies. Missing
decoder data preserves mode; PCM format still imports independently. Channel
tests cover orphan tails, complete publication, incomplete retention, and a
new response replacing a partial frame.

After deployment, a 60-second passive capture recorded 59 MSMCH STEREO replies,
one stable published MULTICHANNEL STEREO value, and stable Active* topology.
The in-memory bounded Rainmeter observer recorded agreement between raw measure,
display measure, and meter text, with PCM separate and all speaker bits stable.
The user confirmed steady MULTICHANNEL STEREO and no speaker-map churn for the
initial reproduction. After the channel correction, the passive capture and
Rainmeter observer followed Stereo -> Dolby Surround -> Multichannel Stereo ->
Stereo. Mode changes were observed at approximately 04:42:46, 04:43:23, and
04:43:46 UTC on September 9. Topology stayed stable during the holds. Brief
intermediate topologies at switches corresponded to actual complete AVR lists,
not tail-only publications. The user confirmed that the final full sequence
followed correctly on the OLED with a stable map between changes.

Box1Collector, DashboardTelemetry.inc, and MeterResponse.inc deployed hashes
still match the unchanged repository files. The Box1 HKLM repair and ballistics
are intact; HKLM Connected/Ready stayed 1 and Sequence advanced. Manager retained
its PID; only the Denon collector was restarted.
Apple Music and artwork state remain active. The isolated TelemetryManager
lifecycle suite passed, including single-instance, restart, transient lock,
failure isolation, and F10/F11 registration checks. Direct process inspection
confirmed one manager, Denon, decoder, and Box1 collector each. WiiM, F10, F11,
and pixel-shift code are unchanged; their interactive regression checks are
not claimed. WiiM bridge, hotkey listener, and pixel-shift deployed hashes also
match the unchanged repository files. A sandbox-blocked test was rerun successfully outside the sandbox;
its leftover fixture manager was stopped by its exact unique script path.

## Deployment and rollback

Only `C:\RainmeterDenon\denon_status.ps1` was deployed. Before writing it, its
backup was created and SHA256 checked at:

`C:\OLED-Telemetry-Project\diagnostics\captures\ListeningMode-deployment-20260908\denon_status.ps1.pre`

Baseline SHA256: `41E930C0066198E911CE195820D7920CFB453F7FB2B0D47B8E84066338DC2B91`.
Final deployed SHA256: `DF5F0DC0F8DC49603B1DC0BF66ED0B9F9BD745CDF23149AC8C913530EFAA9B54`.
The intermediate mode-only version is also backed up beside the baseline as
`denon_status.mode-only.ps1.pre`.

To deploy again: parser-check the repository script, back up the destination to
a new path, verify the backup hash, copy src/denon_status.ps1 to the destination,
verify source/destination hashes, and restart only the exact Denon script process.
The existing TelemetryManager starts its replacement within its supervision cycle.

To roll back, run in an authorized PowerShell session:

```powershell
$ErrorActionPreference = 'Stop'
$backup = 'C:\OLED-Telemetry-Project\diagnostics\captures\ListeningMode-deployment-20260908\denon_status.ps1.pre'
$target = 'C:\RainmeterDenon\denon_status.ps1'
if ((Get-FileHash -LiteralPath $backup).Hash -ne '41E930C0066198E911CE195820D7920CFB453F7FB2B0D47B8E84066338DC2B91') { throw 'Backup hash mismatch' }
Copy-Item -LiteralPath $backup -Destination $target -Force
if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $backup).Hash) { throw 'Restore hash mismatch' }
. 'C:\OLED-Telemetry-Project\src\Utilities\TelemetryProcessIdentity.ps1'
Get-TelemetryScriptProcesses -ScriptPath $target | ForEach-Object { Stop-TelemetryScriptProcess -Process $_ }
# Confirm DenonCollector=Running and a fresh heartbeat in telemetry_manager_status.txt.
```

Captures and backups are Git-ignored. Live user-visible validation passed before
committing this repair. The separate adaptive-gain investigation is not part of
the listening-mode repair commit.
