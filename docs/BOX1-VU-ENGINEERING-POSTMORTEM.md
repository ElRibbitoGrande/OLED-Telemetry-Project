# Box 1 VU Engineering Record and Postmortem

## Status and preservation baseline

Box 1 firmware 0.18 and the Analog_Floating2 VU integration were confirmed
production-good on 2026-08-15. The needles track musical attacks correctly and
have a readable analog-style decay. This document preserves both the final
design and the failed intermediate designs so future telemetry work does not
repeat their mistakes.

Known-good references:

- Production-code baseline: Git commit
  `2e611c67c84fc2e6b92e5e9424f820e41b2b3a90`.
- Annotated Git tag: `v0.18-box1-vu-known-good`.
- Runtime snapshot:
  `C:\RainmeterDenon\Backups\Box1-VU\20260815_120819_214_KnownGood_0.18_RegistryTransport`.
- Snapshot integrity file: `SHA256SUMS.txt` in that folder.
- Firmware was not reflashed while this record was created.

Firmware artifacts, hashed in place:

| Purpose | Artifact | SHA-256 |
|---|---|---|
| 0.17 rollback | `C:\Users\timmeh\Documents\Box1-Firmware\box1-0.17-known-good.uf2` | `76E29B595601556D2000406FDCAEDD02449B46FBF1F855D8136B19C6CEE16AEE` |
| 0.18 current | `C:\Users\timmeh\Documents\Box1-Firmware\box1-0.18-candidate.uf2` | `1985EC0BA5B7B7BE8E39624E688C28EA1E907B8C35D6349C8CFFFF17C5D790C1` |

## Final working architecture

The production signal path is:

```text
PCM1808 stereo ADC
  -> Raspberry Pi Pico 2, Box 1 firmware 0.18
  -> USB CDC serial telemetry at approximately 100 records/second
  -> Box1Collector.ps1 continuous serial acquisition
  -> raw LeftRmsDb / RightRmsDb converted to linear amplitude
  -> AudioLevel-equivalent asymmetric power-domain envelope at collector rate
  -> nonvolatile HKLM\SOFTWARE\OLED-Telemetry-Project\Box1Runtime values
  -> Rainmeter native Registry measures once per actual skin frame
  -> existing gain 2.7 and clamp to 0..1
  -> exact LYR+ source/usability gate
  -> Analog_Floating2 left and right needle rotations
```

`Box1Collector.ps1` remains a TelemetryManager-managed child process. It keeps
COM3 open continuously with DTR and RTS enabled, parses every complete valid
record, increments `Sequence` once per accepted serial record, and updates the
power envelope before returning to `ReadLine()`. Acquisition never waits for
state publication.

The collector converts RMS dBFS using:

```text
amplitude = clamp(10^(dBFS / 20), 0, 1)
targetPower = amplitude^2
```

For each telemetry interval, it applies the same power-domain response used to
model Rainmeter AudioLevel:

```text
responseMs = targetPower < currentPower ? decayMs : attackMs
coefficient = exp(log10(0.01) * elapsedMs / responseMs)
currentPower = targetPower + coefficient * (currentPower - targetPower)
envelope = sqrt(max(0, currentPower))
```

The settings remain attack 85 ms and decay 520 ms. Rainmeter applies the
existing gain of 2.7 after the envelope and clamps the final result to 0..1.
These settings are coefficient inputs, not a separately invented conventional
one-pole time constant. No peak signal, firmware `vu` field, rolling maximum,
hold, moving average, decimation, or artificial pacing is in the needle path.

The publisher writes the current envelope and supporting state to a
nonvolatile 64-bit HKLM key. The deployment gives the collector's user
`ReadKey|SetValue` access and gives restricted application tokens read access;
it does not grant broad write access. Values include raw RMS, the processed
left/right envelopes, connection/readiness, timestamp, and sequence. `Sequence`
is written last as the commit marker. Rainmeter's native Registry measures
synchronously query the current values at each actual skin update. Persistence
does not make old values usable: the existing five-second sequence-freshness
guard requires `Sequence` to advance after the skin starts.

The atomic `box1_status.txt` file remains for compatibility, diagnostics, and
human inspection, but it is no longer in the time-sensitive needle path.
Existing five-second sequence freshness, `Connected=1`, `Ready=1`, and exact
`Source=LYR+` gating remain in force. Every non-LYR+ source still uses the
unchanged Windows expression:

```text
DashboardVURawLeft * DashboardLevelSourceCode
DashboardVURawRight * DashboardLevelSourceCode
```

## 2026-09-03 Lyr+ stationary-needle incident

The downstream failure boundary was established from a naturally occurring
live failure. WiiM music produced changing stereo values in
`box1_status.txt`, the collector remained single-instance and healthy, and the
AVR source changed correctly, but the rendered Analog_Floating2 needles did
not move on LYR+.

The diagnostic comparison capture at
`diagnostics\captures\Box1VUComparison_20260903_212326_479` isolated the
divergence. Across 5,892 Rainmeter frames, all ten HKCU Registry measures
remained on the same obsolete committed state, including
`Sequence=7692374`, while the same running collector's current registry and
file sequence had advanced beyond 9.6 million and continued changing. Disabling
and re-enabling the measure, forcing a measure update, and rewriting the key
did not make Rainmeter acquire the current HKCU object. A new HKCU parent and
runtime key also remained invisible to Rainmeter. This ruled out Box 1,
serial acquisition, collector publication, source selection, meter ballistics,
and the five-second freshness logic.

The demonstrated failure mechanism was a cross-process HKCU namespace mismatch
between the collector and Rainmeter. Rainmeter was repeatedly querying a
different, stale HKCU object. The captures establish the namespace split, but
do not identify which Windows isolation layer created it. The source gate then
behaved safely: the unchanged sequence failed the freshness test, so LYR+
received a resting fallback instead of stale meter motion.

The smallest reliable repair moved only the synchronous current-state transport
to `HKLM\SOFTWARE\OLED-Telemetry-Project\Box1Runtime`, explicitly using the
64-bit registry view and a scoped ACL. The collector-side envelope, registry
value names, commit-marker order, source gate, gain, ballistics, and displayed
meters were not changed. A nonvolatile key is required because Windows does not
permit a nonvolatile child beneath the earlier volatile parent. Persisted state
is safe because the sequence-freshness guard remains authoritative.

The post-repair capture at
`diagnostics\captures\Box1VUComparison_20260903_225311_825` recorded 8,113
Rainmeter frames and 8,109 unique collector sequences observed by Rainmeter,
with no raw collector sequence gaps. The user then visually confirmed every
required state: movement on LYR+, independent musical response, decay to rest
on WiiM pause, movement on resume, rest on HTPC while WiiM continued, and
correct behavior across repeated HTPC/Lyr+ transitions.

## Confirmed results

Firmware 0.18 and the decoupled collector repeatedly measured approximately
100 Hz, including 100.4 Hz and 100.5 Hz checks. The final controlled capture at
`diagnostics\captures\Box1VUComparison_20260815_115008_031` measured:

- raw collector acquisition: approximately 100.07 Hz;
- Rainmeter frames: 241;
- unique Box sequences seen by Rainmeter: 241;
- actual Rainmeter frames receiving fresh Box state: 100%;
- adjacent repeated sequences: 0;
- non-monotonic sequences: 0;
- collector errors: 0.

Rainmeter was executing about 22.54 actual frames/second during that short
capture rather than the theoretical 31.25 frames/second implied by
`Update=32`. Each real frame nevertheless received a newer committed Box
sequence. The median jump of five raw records between frames is expected:
those intermediate records had already contributed to the continuously
updated envelope before Rainmeter sampled its current value.

The final subjective result is also important engineering evidence. The
needles now track the music correctly. They appear smoother, more organic, and
less twitchy than the HTPC AudioLevel path, with a slower mechanical-looking
fall while remaining attached to kicks, snares, hand claps, piano attacks, and
other transients.

## Failed file/WebParser architecture

The critical failed path was:

```text
100 Hz Box collector
  -> box1_status.txt replacement
  -> asynchronous Rainmeter WebParser file:// parent
  -> dependent WebParser child measures
  -> 32 ms Lua envelope
  -> needles
```

`UpdateRate=1` did not mean a completed local-file read on every skin frame.
Rainmeter WebParser starts an asynchronous worker only when no previous worker
is active. Dependent child WebParser measures receive new substrings only after
the parent worker successfully reads and parses the entire file. There is no
useful intermediate queue of Box records.

For `file://`, WebParser still uses its asynchronous download/read path.
Rainmeter's `FileUtil::ReadFullFile()` opens the file through `_wfopen_s` in
binary-read mode. That CRT open is non-shareable. It repeatedly contended with
the collector replacing `box1_status.txt` through `ReplaceFileW`. A worker that
failed to open or parse retained the previous child values, and another worker
could not begin until the current worker finished. Local WebParser caching was
not the cause, and there was no explicit built-in 5 Hz limit; serialized worker
completion, sharing contention, and the skin's lower real update rate produced
the observed irregular cadence.

The long simultaneous comparison capture contained:

- 30,029 collector records in 300.354 seconds, approximately 100 Hz;
- zero raw sequence gaps;
- 6,684 Rainmeter frames;
- only 1,162 unique Box sequences observed by Rainmeter;
- actual unique-state delivery approximately 3.87 Hz when measured against
  collector wall time, not the initially reported 5.4 Hz based on compressed
  nominal Rainmeter time;
- 416 prominent raw events;
- 403 of 416 events whose exact raw sequence was never observed by Rainmeter;
- 320 of 416 events without a Box-final event within 160 ms.

The fitted clock slope of `0.715578404` was principally an artifact of treating
`RainmeterFrame * 32 ms` as wall time. The 6,684 nominal frames represented
about 213.856 nominal seconds but spanned roughly 300 seconds of collector wall
time. It did not justify a hardware-clock-drift conclusion.

This sparse, irregular sampling happened before the Lua response and therefore
made short peaks appear missing and latency appear variable. Values were
numerically exact whenever Rainmeter did observe a sequence; delivery, not RMS
conversion, was broken.

Windows AudioLevel did not suffer this failure because its WASAPI producer and
power envelope run continuously in-process. Rainmeter reads the plugin's
current processed value. It does not place an asynchronous text-file parser
between acquisition and the envelope.

## Other failures and lessons

### Synchronous collector publication

The first host collector performed `ReadLine()`, parsing, timestamp formatting,
atomic state-file publication, and error clearing serially for every sample.
The filesystem work delayed the next serial read and limited observed host
throughput to approximately 27.7 Hz. Moving state publication to an independent
publisher restored approximately 100 Hz acquisition. `Sequence` now advances
for every valid received record independently of publication, while the
publisher naturally coalesces to the newest sample if it is busy.

### Windows file replacement

`Move-Item -Force` did not provide continuously readable replacement semantics
for this workload. Concurrent readers observed transient missing-path and
access-denied failures.

An attempted `[System.IO.File]::Replace($temp, $path, $null)` then failed under
Windows PowerShell 5.1 with "The path is not of a legal form." PowerShell's
overload binding converted the intended null backup filename to an empty
string. A minimal `ReplaceFileW` P/Invoke, with a native null backup pointer and
flags zero, fixed atomic publication without per-update backup churn. This
solved the publisher replacement problem but could not make WebParser deliver
fresh values reliably; the reader architecture still had to be removed from
the VU path.

### Response experiments

Firmware 0.18 publishes raw `rms`, `peak`, and firmware-smoothed `vu` fields.
The firmware `vu` field, nominally smoothed near 300 ms attack and 900 ms decay,
was not in the final RMS needle path. Raw `LeftRmsDb` and `RightRmsDb` are the
authoritative inputs.

An early Lua implementation interpreted 85/520 as ordinary amplitude-domain
exponential time constants. That did not match AudioLevel. AudioLevel carries
power state, chooses attack or decay by comparing target power to current
power, updates with the coefficient shown above, takes the square root, then
applies gain and clamps. The deterministic comparison test covers step-up,
step-down, short pulse, repeated pulses, direction reversals, changing targets,
gain, and clamp behavior.

An immediate-attack Lua experiment improved one symptom but did not reproduce
AudioLevel and could not restore transients that WebParser never delivered.
Moving the correct power response to the continuous producer boundary solved
the real problem without inventing a peak/hold scheme.

At one point repository and deployed `Box1VUResponse.lua` copies differed after
a live rollback and a later source experiment. Reasoning from source alone
therefore produced false assumptions about the active attack behavior. Always
hash both source and deployed files before diagnosing a live signal path.

### Diagnostic capture defects

The comparison tooling exposed its own boundary bugs:

- A disabled Rainmeter Script measure had already passed its useful
  initialization lifecycle before the capture control file existed. Enabling
  it did not reliably re-run the intended initialization. In addition,
  `!CommandMeasure ... "Initialize()"` routes the command text through a
  Script measure's `Command(command)` callback; it does not directly call an
  arbitrary Lua global. The diagnostic measure was made self-arming from
  `Update()` when inactive.
- Lua originally opened the control file in binary mode. A CRLF carriage
  return remained attached to the parsed `CaptureDirectory`, corrupting the
  path. Text-mode reading normalized the line endings and fixed the capture
  directory.

The successful diagnostic design instrumented both sides independently:

- collector-side raw logging recorded every accepted record with a
  high-resolution timestamp and sequence;
- Rainmeter-side logging recorded each actual frame, the raw RMS received,
  pre-response amplitude, final response, source, and sequence.

Sequence numbers and timestamps at every boundary made it possible to
distinguish acquisition loss, publication loss, parser loss, envelope behavior,
and display gating. Cross-correlation was necessary because Windows and WiiM
playback could not start simultaneously. Subjective timing guesses alone had
previously conflated transport loss, response shape, and source offset.

## Box 2 and future telemetry requirements

Future telemetry devices may use different microcontrollers or host boards and
may combine HDMI information, analog information, AVR polling, Windows
telemetry, and streaming-device polling. Box 1 is a lesson in boundaries and
serviceability, not a mandate to reuse one board or protocol.

Requirements for future designs:

- Avoid slow polling or file-parser intermediaries in time-sensitive telemetry
  paths.
- Keep continuous producers independent from display publication and verify
  both rates separately.
- Put monotonic sequence numbers and meaningful timestamps at acquisition,
  publication, transport, and display boundaries.
- Prefer synchronous local IPC, or a continuously processed current-state
  interface, for frame-rate telemetry.
- When the display cannot consume every raw record, perform the required
  response continuously upstream and expose current processed state, as
  AudioLevel does.
- Prove disconnect recovery, update paths, rollback, and serviceability before
  finalizing an enclosure.
- Preserve firmware and runtime rollback artifacts before transport or
  architecture changes.
- Validate correlation with controlled captures rather than judging latency
  from unrelated playback clocks.

## Mechanical and enclosure lessons

Box 1's enclosure was nearly too small. Cable stiffness and minimum bend radius
consumed substantially more internal volume than the component outlines
suggested. The external USB-C panel connector assumed a thinner wall or a
recessed mounting surface. Its mounting ears had to be sheared off, and the
connector was pushed into the enclosure with an ill-fitting grommet.

Future enclosure models must explicitly include:

- connector flange and mounting-ear geometry;
- actual wall thickness;
- countersunk or recessed port geometry;
- insertion depth on both sides of the wall;
- cable bend radius and connector boot stiffness;
- strain relief;
- service loops;
- unplug/replug clearance with the enclosure assembled;
- access for firmware update, BOOTSEL/recovery, and diagnostic probing;
- deliberate spare volume rather than a zero-clearance component fit.

Box 2 should likely use a larger 3D-printed enclosure designed around cable
routing, recessed connectors, recovery access, and serviceability rather than
minimum external dimensions.

## Recovery notes

The known-good snapshot contains the active skin INI, the complete relevant
include chain, VU response configuration, diagnostic Script dependency,
collector, TelemetryManager, launcher, restore mapping, and manifest. Restore
only from the manifest-verified snapshot, retain current files as a new backup
before overwriting, restart only the managed Box 1 collector if its script is
restored, and refresh only Analog_Floating2 if its files are restored.

After recovery verify:

1. `Box1Collector.ps1` is a single TelemetryManager child.
2. `HKLM\SOFTWARE\OLED-Telemetry-Project\Box1Runtime` reports Connected and
   Ready as 1 and its Sequence advances near 100 Hz.
3. `box1_heartbeat.txt` is fresh and no fresh `box1_status_error.txt` exists.
4. Analog_Floating2 sees a newer Box sequence on every actual frame.
5. Non-LYR+ VU behavior remains the unchanged AudioLevel fallback.

## Deployment and rollback for the HKLM repair

Validate from `C:\OLED-Telemetry-Project` before deployment:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\diagnostics\Test-Box1VUResponse.ps1
```

Then run the deployment helper from an elevated PowerShell session:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OLED-Telemetry-Project\diagnostics\Deploy-Box1VURegistryRepair.ps1
```

The helper backs up both deployed files, provisions the 64-bit HKLM key and
ACL, copies and hash-verifies the files, restarts only the manager-owned Box 1
collector, and verifies a single replacement process plus an advancing
sequence. Refresh only `Analog_Floating2` afterward; a Rainmeter application
restart is not required.

The validated production rollback directory is
`C:\RainmeterDenon\Backups\Box1-VU-Lyr-Repair\20260903_225209_209`.
To roll back, first preserve the current deployed files, then restore
`Box1Collector.ps1.pre` to `C:\RainmeterDenon\Box1Collector.ps1` and
`DashboardTelemetry.inc.pre` to the skin's
`@Resources\Includes\DashboardTelemetry.inc`. From an elevated session remove
only `HKLM\SOFTWARE\OLED-Telemetry-Project\Box1Runtime`, restart only the
manager-owned Box 1 collector, and refresh only Analog_Floating2. The older
collector recreates its original HKCU transport. Verify one collector, fresh
heartbeat/status, advancing HKCU sequence, and normal needle behavior.
