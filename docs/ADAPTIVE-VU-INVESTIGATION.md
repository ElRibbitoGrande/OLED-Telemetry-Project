# Adaptive meter sensitivity and Lyr+/Box1 timing — investigation in progress

## 2026-10-11: paired recordings show residual latency; acceptance pending

The new responsiveness task supersedes the former Lyr+ display-blackout
constraint. The user can retain the PC/HDMI display, interact with Codex, and
record the OLED while listening to Lyr+. Historical timed/blind capture accounts
below describe the former arrangement. Do not repeat that workflow.

The September trial files in the working tree matched the deployed skin.
Their 1.6 Box1 calibration, unity AudioLevel acquisition, stereo-linked adaptive
attenuation and 85/520 ms coefficients are preserved. No adaptive target, gain
limit, attack/decay constant, source gate, firmware or watchdog logic was changed
in this delivery trial. Completion still requires a controlled audible/visual
comparison; quieter software delivery is not proof of perceptual acceptance.

### Paired Black Cow recordings: measured residual offset

The user supplied separate synchronized 4K recordings of Black Cow through
Windows/Apple Music and Schiit/Lyr+/WiiM. Both are 3840x2160 HEVC at nominal
60000/1001 fps with 48 kHz stereo AAC. The OLED source label and diagnostic
SYNC footer are visible. Windows shows volume 65 and Dolby Surround; Lyr+
shows volume 60 and Stereo. This is a timing comparison across different
playback paths, not a matched electrical-level or identical-master experiment.

The bounded capture `Box1VUComparison_20261011_172641_742` completed all three
writers. It contains 18,134 valid raw records at 99.97 Hz: receipt spacing
median/p95/p99/max 10.00/14.99/16.92/26.62 ms. Sampled receipt-to-first-HKLM
observation is 10.11/17.23 ms median/p95; latest-data age at the sampled command
clock is 7.15/12.23 ms. Actual command cadence remains about 46.60 ms median,
48.04 ms p95. No malformed tail was present. These are software delivery
measurements, not physical latency sums.

Analysis used the first 15 seconds of each video, retaining original packet
presentation timestamps. The left needle was measured by positive brightness
above a static median background along candidate radial lines. Six sampled
frames per recording were visually checked against the extracted angles.
An affine-independent pattern alignment to logged left display values gives
correlations 0.993 for Windows and 0.982 for Lyr+. This verifies the measured
needle trace follows the command pattern; maximizing that alignment alone
cannot independently measure render delay. The readable Lyr+ footer near
video 8 seconds is `SYNC 1791764975.026`, consistent with the matched log row.

The capture ends around 17:29:43 local time, approximately 16 seconds into
the Lyr+ recording. The later video remains useful as visual/audio evidence,
but has no corresponding high-rate telemetry in this capture. No missing
late rows have been invented. The numerical results below use only the
overlapping portion. Local scratch analysis, crops, traces and result JSON
are retained under ignored `diagnostics/captures`, not committed as media or logs.

Phone audio was decoded to mono 8 kHz and measured in 10 ms RMS blocks. Applying
the same illustrative 85/520 power envelope to that microphone reference gives
the following pattern alignments. Positive lag means the needle follows the
microphone-derived envelope. This common block model is not an exact recreation
of AudioLevel's per-sample asymmetric envelope.

| Comparison | Best pattern lag | Correlation / repeatability |
|---|---|---|
| Windows needle vs common microphone envelope, video 5–14 s | -10 ms | 0.816; three subwindows -20/0/-10 ms |
| Lyr+ needle vs common microphone envelope, video 2–14 s | +60 ms | 0.816; three subwindows +70/+60/+50 ms |
| Lyr+ raw left/right RMS vs microphone RMS | +40 ms each | 0.751/0.758; all three subwindows +40 ms on both channels |
| Lyr+ raw left/right peak vs microphone RMS | +40 ms each | 0.666/0.674 |
| Same 85/520 envelope applied to Lyr+ raw RMS and microphone RMS | +50 ms each | 0.819/0.828 |

The recordings support the user's residual-lag observation. They suggest much
of the offset is already present in incoming raw RMS and peak patterns, before
the collector's attack/decay envelope. They do not establish a precise 40 ms
hardware delay or identify its individual source. The raw-data comparison uses
a video start fitted to command/needle motion, so its optical/display offset
remains part of the estimate. Microphone AGC, room acoustics, mono mixing,
different masters and downstream audio processing also change the reference.
Camera frame timing, exposure and sampled probe clocks add uncertainty; 10 ms
search increments are computational resolution, not a confidence interval.

Consequently no attack/decay or adaptive-gain retuning was selected from this
evidence. Shortening attack would risk compensating for an upstream offset
while changing the musical envelope. The next useful inspection is the actual
firmware 0.18 RMS/peak integration window, sample/DMA buffering and USB report
path. Only UF2 artifacts have been located so far; build source is needed to
make a narrowly scoped, reproducible firmware change. No firmware was flashed,
production code changed, or second physical recording session requested in
this analysis. Perceptual equivalence and task completion remain unproven.

### Measured path and limits

| Stage | Evidence / contribution |
|---|---|
| WiiM analog event relative to heard audio | Paired phone recordings now provide a microphone-relative pattern reference as described above. An electrical analog-event timestamp remains unavailable; playback/source clocks are not timing references. |
| PCM1808 conversion/filter | TI specifies digital-filter delay 17.4/fs; 0.36 ms at 48 kHz, conditional on actual fs. Current fs has not been independently verified. |
| Pico sampling, raw RMS window and USB batching | Firmware 0.18 emits approximately 100 reports/s. Window length, DMA buffering and sample timestamps remain unknown; only UF2 artifacts were found, not build source. A 10 ms report period does not prove a 10 ms RMS window. |
| Serial receipt | About 100 Hz. Completed baseline median spacing 9.94 ms, p95 16.65 ms, p99 25.28 ms; post-change 9.96 / 15.74 / 22.58 ms. Acquisition is continuously decoupled from publication. |
| Collector envelope | One asymmetric power envelope over raw RMS reports, 85/520 coefficient inputs. Firmware `vu` is diagnostic and is not used for needles. No new envelope stage in Rainmeter. |
| Receipt to first HKLM observation | Sampled baseline median/p95 14.9/24.8 ms; post-change 10.0/17.4 ms. Includes observer waiting, not just publisher processing. |
| Receipt to command-frame clock estimate | Sampled baseline median/p95 13.2/22.5 ms; post-change 7.4/14.5 ms. This is latest-data age, not physical onset or scanout. |
| Source mapping/calibration and linked gain | Scalar multiplication, one slow linked gain, final clamp. Gain interpolation affects gain only; the accepted normal-material example held gain at one. |
| Rainmeter command cadence | Nominal 32 ms, observed median approximately 46.5–46.7 ms on this desktop. Both sources share rendering cadence. No frame-rate change was made. |
| Render/panel/camera/acoustic delay | Not independently measured; must not be omitted from claimed end-to-end latency. |

These numbers are not additive end-to-end measurements. The diagnostic clock
is sampled every requested 5 ms, actually about 15.6 ms on this host, with
observed gaps up to 47–62 ms. Its frame timestamps therefore have bounded
sampling uncertainty, plus millisecond receipt truncation. Initial stale probe
clock values are excluded. Before/after statistics support reduced software
delivery overhead; their apparent 5–8 ms difference is not a precise measured
physical latency improvement. Captures contained silent Box1 input, so these
new recordings establish delivery/idle stability rather than musical acceptance.

References: [TI PCM1808 datasheet](https://www.ti.com/lit/gpn/pcm1808),
[installed-version AudioLevel source](https://github.com/rainmeter/rainmeter/blob/v4.5.26.3894/Plugins/PluginAudioLevel/PluginAudioLevel.cpp).
The firmware artifact SHA256 still matches the August known-good 0.18 artifact;
no flashing or physical AVR/audio-control changes were performed.

### Avoidable overhead and stability changes

The same publisher worker previously wrote live HKLM values and a diagnostic
status file on every approximately 100 Hz update. Rainmeter no longer reads that
file. Its only active code consumer found in this audit is collector startup
sequence recovery. Diagnostic snapshots now write at most 5 Hz while HKLM remains
signaled at acquisition rate and coalesces only intermediate publication samples.
Startup chooses max(registry sequence, diagnostic-file sequence), preserving
monotonicity despite the slower file. No fixed sleep or pacing was introduced in
serial acquisition or the envelope.

The manager log recorded temporary missing heartbeat paths followed by Box1
restarts, including during an initial capture. Heartbeat publication now opens
the existing file in place and closes it after writing instead of replacing its
directory entry. Its mtime remains liveness evidence only. This removes a
plausible transient-absence trigger without relaxing supervision or changing
TelemetryManager/watchdog code. The interrupted capture is labeled incomplete;
its malformed final row is excluded, never silently treated as a complete run.

`Test-Box1DeliveryPublisher.ps1` executes the real publisher in an isolated HKCU
fixture with synthetic data. A diagnostic file held without delete-sharing did
not stop live registry updates; the heartbeat progressed and final sequence
committed. It observed 21 diagnostic snapshots over 400 input updates. Values
and stereo ratio remained intact. Native HKLM transport and its scoped ACL in
production remain unchanged. The completed post-deployment capture held about
100 Hz and had all capture completion markers, without a collector restart.

### Ballistics versus windowing

The existing constant-power equivalence tests pass, but cannot establish
equivalence to real PCM audio. AudioLevel applies attack/decay per sample of
squared audio, including waveform zero crossings. Box1 applies that operation
to an already-averaged RMS power value. Averaging and asymmetric filtering do
not commute. `Model-VUEnvelope.py` makes this distinction explicit: for its
illustrative 1 kHz amplitude step, own-steady-level-normalized 90% rise was about
158 ms for audio-sample filtering and 90 ms for 10 ms RMS blocks. Other unknown
window lengths shift onset and shape. These are simulations, not measured Box1
firmware behavior. They do not justify blindly reducing attack; the current
user observation of slower Lyr+ attack remains valid acceptance evidence.

Replaying the accepted Black Cow raw capture with receipt-timed versus nominal
10 ms steps changed median travel 0.363 to 0.368 and p95 0.560 to 0.562, with
no pinning. That is small and does not establish receipt jitter as the residual
audible-delay cause. Consequently neither time-base nor ballistics was retuned.
No second fast envelope, peak hold or moving average was found downstream in
the deployed needle path. The firmware's raw RMS window is an unresolved upstream
integration stage, distinct from its unused `vu` envelope.
In the accepted Black Cow raw capture, peak/RMS dB alignment was strongest at
zero report lag (correlation 0.988). This supplies no evidence of a separate
RMS lag relative to peak; both fields can still share an unknown upstream window.

### Validation and regression scope

PowerShell parsing and the existing constant-power step/pulse/gain tests passed.
Rainmeter's actual Lua runtime passed adaptive tests for isolated peaks,
stereo linkage, silence/pause hold, no wind-up, source/track resets and bounded
gain interpolation. Five recorded normal/hot replays passed: normal replays
retained unity adaptive gain; settled hot pinning remained 0.138% HTPC and
0.435% calibrated Box1. Sparse/quiet behavior is covered by synthetic levels
and existing dynamic passages, not by an invented new quiet recording.
The watchdog reports healthy critical state and updating presentation with no
RESET AVR. Its code, mode authority, artwork controller, hotkeys and pixel-shift
code are outside this change. A historical watchdog restart occurred before
the collector deployment; it is not claimed to have been solved by this VU work.

### Instrumentation, callers and failure isolation

- `Box1Collector.ps1` is called by TelemetryManager; reads serial, previous
  diagnostic sequence and HKLM sequence; writes live HKLM, 5 Hz `box1_status.txt`,
  2-second heartbeat, errors and optional capture logs. Connection/validation/
  reconnection/shutdown deadlines retain 750 ms / 6 s / 2 s / 5 s behavior.
- `Capture-VUProgram.ps1` calls Start/Stop capture scripts and stops automatically
  in finally. Start launches bounded `Probe-Box1Delivery.ps1`, enables the optional
  registry clock measure and Lua capture, with an 8-second startup/error deadline.
  Stop removes the control file, hides/disables capture and clock, and checks
  existing 12-second completion deadlines. A probe error does not restart collectors.
- The C# probe writes only a diagnostic clock value in the existing writable
  runtime key and CSV/markers under ignored captures. It opens exactly ReadKey /
  SetValue access, never broadens ACLs, and stops on control removal or 330 seconds.
  It never opens the serial port. Its record timestamps are sampled observations.
- Lua appends clock/receipt columns, buffers bounded capture rows, and temporarily
  shows a small SYNC footer in AF2 for video-to-log alignment. The footer is hidden
  outside capture. Disabled diagnostics add no ongoing clock writes or logging.
- Publisher-file failures cannot block acquisition or unrelated telemetry.
  Only Box1 was restarted for deployment; no AVR, Windows, metadata or watchdog
  restart is part of VU deployment.

### Deployment and exact rollback

The VU-only deployment tool verifies backups/hashes before copying explicit VU
files, the AF2 layout footer, and optionally Box1Collector. It refreshes only AF2.
Collector replacement is supervised by the existing manager. Firmware and
watchdog files are never in this deployment list.

The original pre-change collector and improved September VU behavior are preserved
in `diagnostics/captures/VU-latency-backup-20261011-164138`. The earlier instrumentation
backup at `VU-latency-backup-20261011-162030` preserves the pre-clock VU include/Lua
files. The final sync-footer deployment is backed up in
`VU-latency-backup-20261011-165953`, including the prior AF2 layout. All backup
hashes were verified. Git commit `a122e6c` preserves the pre-change deployed
adaptive trial on top of watchdog baseline `4ee175e`.
To undo delivery changes while retaining the AVR watchdog:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\OLED-Telemetry-Project\diagnostics\Deploy-VULatency.ps1 -Action Rollback -BackupPath C:\OLED-Telemetry-Project\diagnostics\captures\VU-latency-backup-20261011-164138
```

To additionally remove timing diagnostics, restore the earlier instrumentation
backup with the same command. Restore the `165953` manifest first if the inert,
normally hidden sync-footer definition must also be removed. Each manifest is validated against hashes and the
explicit allowed target list. Existing adaptive/calibration behavior is retained.
Generated logs, clock state and cached artwork are not committed.
The final short capture completed both acquisition and Rainmeter logs. Native
inspection confirmed the foreground sync meter and updated timestamp text;
capture/clock measures were disabled afterward. Read-only production runtime
validation confirmed one copy of every supervised component, healthy independent
AVR verification, current Rainmeter consumption and no reset warning.

### Remaining physical comparison

Instrumented command times cannot show when the analog event reached the ADC,
the actual rendered scanout, or the user's acoustic reference. A single paired
recording session is therefore required before final completion: same 30-second
Black Cow passage on HTPC and Lyr+, preferably 60 fps from the same camera position,
showing both needles, source and SYNC footer with music audible. No HDMI input
change, blind wait or manually estimated milliseconds is required. Timing analysis
will distinguish delayed onset from slow approach after onset before choosing
an attack/firmware change. No perceptual equivalence has yet been claimed.

The additional September 8 request authorizes slow, stereo-linked adaptive
meter gain for HTPC and Lyr+/Box1. It does not authorize replacing the pleasing
HTPC motion with a different response. Base gain remains 2.7 and attack /
decay remain 85 / 520 ms. A first attenuation-only trial is now deployed;
user-visible validation and quiet-recording gain increases remain outstanding.

## September 8 trial (historical, 23:16)

The later paired Corea capture aligned at correlation 0.968 with a fitted
Box1-to-Windows multiplier of 1.66. Aja suggested 1.605. A provisional 1.6
Box1 calibration therefore precedes shared sensitivity. The paired capture
contained 100 Hz acquisition without sequence gaps, about 22.8 display frames/s,
and fresh Box1 sequence values on 98.8% of frames. Faster attack candidates
worsened the aligned fit; retain 85/520 pending perceptual validation. Player
start offsets are included in alignment lag; this is not a hardware latency test.

AdaptiveGainCore.lua consumes the unclipped, calibrated envelope and uses one
linked maximum for both channels. Twenty completed one-second buckets qualify
attenuation only when at least 10% of recent values remain pinned. Its p95
target is 0.90, minimum gain -6 dB, downward rate 0.15 dB/s. Pauses and silence
discard statistics and hold gain. Source/track changes reset sensitivity to
baseline. Upward gain is deliberately pending a real quiet recording. The Lua
adapter interpolates gain steps only, without smoothing the music envelope.
Statistics are bounded to 20 buckets of at most 256 samples each. Clock gaps
discard history. There is no network access, polling, retry loop, or per-frame
file I/O in the controller; missing core falls back to fixed sensitivity.

Native Rainmeter Lua tests passed for isolated transients, bounded hot gain,
pause/silence, source/track reset, adapter smoothing, and five real replays.
Normal replays retained unity adaptive gain. Final hot replay pinning was
0.138% HTPC and 0.435% calibrated Box1. These are replay results, not user
validation. MeterResponse.inc is included by Analog_Floating2.ini; its two
display measures feed the existing needles. Legacy raw/final diagnostic
measures retain their original fixed-gain definitions. Capture now records
AdaptiveGain and Box1CalibrationGain alongside the actual display commands.

Deployment: back up all five VU files and record existence/hash first; copy
SignalAcquisition.inc, MeterResponse.inc, Box1VUComparisonCapture.lua,
AdaptiveGain.lua and AdaptiveGainCore.lua from src/@Resources/VU to the skin's
@Resources/VU, verify source/deployed SHA256, then run Rainmeter.exe
`!Refresh Analog_Floating2`. This procedure was executed with matching hashes.
Backup: diagnostics/captures/VU-adaptive-backup-20260908-231612/manifest.csv.
Rollback: restore every Existed=True file from this backup to its exact
Destination after verifying OriginalHash, then refresh Analog_Floating2.
The two new Lua files may remain inert after restoring MeterResponse.inc;
no deletion is necessary. This rollback preserves the earlier headroom capture
instrumentation. The separate VU-headroom backup restores that instrumentation
if needed. No collector, HKLM transport, or listening-mode file changed.

Earlier sections below record the investigation before this trial and may
describe stages when no controller was deployed.

### First live Lyr validation

Black Cow capture Box1VUComparison_20260908_235207_041 completed with both
loggers: 9,098 raw records at 100.08 Hz, no sequence discontinuities, 2,060
display frames at approximately 22.63 Hz. Receipt interval p99 was 26.36 ms,
maximum 63.67 ms; 99.51% of frames read a distinct Box1 sequence, with at most
two consecutive frames holding one sequence. Adaptive gain remained exactly
1 throughout; calibrated display median was 0.364, p95 0.561, pinning 0%.
The user reports motion is a great deal better, but still appears slightly
behind audible music compared with Apple Music on HTPC. This is partial
perceptual validation, not latency acceptance. Since gain stayed constant,
gain interpolation cannot explain the residual delay in this recording.

The collector publishes the latest sample and coalesces intermediate samples;
no additional fixed publication sleep was found. Healthy receipt cadence does
not rule out a constant delay upstream. The capture timestamps do not provide
a synchronized audible reference, and frame timestamps have only one-second
resolution; they cannot quantify millisecond audio-to-needle latency. Input
RMS windowing, transport, and display scheduling remain candidates, not proven
causes. Preserve the improved calibration while investigating timing separately.

## What existing captures establish

`diagnostics/Analyze-VURange.py` reports per-channel and stereo-linked
distributions, active-only distributions, and one-second means/peaks. The linked
statistic in this analysis is max(left,right), so a loud channel is not hidden
by averaging with a quiet channel. This is descriptive analysis, not a chosen
control law. Descriptive bins are rest <0.05, midrange 0.05–0.8, upper range
0.8–0.99, and effectively pinned >=0.99 of needle travel. Capture durations use
observed epoch seconds rather than the inaccurate nominal 32 ms frame clock.

The September 3 post-registry-repair capture contains 135 observed seconds on
LYR+: linked median 0.235, p95 0.422, 12.4% rest, 87.4% midrange, 0.1% upper,
and no material pinning. Its HTPC segment is effectively silent and cannot
calibrate Windows against Box1. Earlier September 3 captures include stale
registry transport and are not valid gain-design evidence.

The first fresh September 8 capture contains 83 observed HTPC seconds spanning
the end of Josie and start of Black Cow from Aja: linked median 0.196, p95 0.407,
32.7% rest, 67.3% midrange, no upper-range or pinned samples. The fade / gap
must not be interpreted as an ordinary quiet recording needing more gain.
The sustained Black Cow follow-up contains 91 observed seconds, with linked
median 0.396 and p95 0.578; all samples are in the defined midrange and none
are pinned. The logged portion spans approximately positions 74–163 seconds.
This is the first usable sustained HTPC reference for the new controller.

Track labels and detailed reports stay in Git-ignored captures. More examples
are required before setting gain bounds, target distribution, window length,
or asymmetric rates. Quiet and hot recordings are not yet characterized.

The confirmed LYR+ Black Cow sample (`Box1VUComparison_20260908_221946_334`)
contains 91 observed seconds: linked median 0.231, p95 0.352, all samples in
the defined midrange, no pinning. WiiM reported Amazon Music, while the HTPC
reference used Apple Music. Compare-VUTrack.py matched ten reported playback
positions between approximately 73 and 92 seconds; the median ratio of HTPC
to Box1 per-position levels was 1.605, or 4.11 dB. This suggests a sensitivity
difference but cannot distinguish source calibration from differing masters,
service normalization, or playback gain. No calibration constant is selected.

An earlier attempted Lyr+ capture (`Box1VUComparison_20260908_221710_269`)
actually recorded HTPC/Deacon Blues and Peg. It is not treated as Lyr+ data.
The corrected capture was armed to wait for LYR+ and Black Cow, then stopped
automatically after 90 seconds.

## Hot material and unclipped measurement

The Expert (Yello, Touch Yello Deluxe Edition) on HTPC, capture
`Box1VUComparison_20260908_222732_207`, contains 91 observed seconds: linked
median 0.959, p95 1.000, 22.5% midrange, 34.1% upper range, and 43.4%
effectively pinned. This establishes a real need for attenuation on sustained
hot material and makes the old clipped measurements insufficient for estimating
the required gain reduction.

SignalAcquisition.inc now exposes AudioLevel's unity-gain envelopes, retaining
the original 85/520 ms audio-rate response. Compatibility measures apply the
original 2.7 multiplier and clamp. Thus current display behavior remains
`clamp(envelope * 2.7)` on both paths; adaptation is still not enabled.
Box1VUComparisonCapture.lua appends unclipped envelopes and actual final display
commands while preserving existing CSV columns. A 240-frame live check while
Bostich (Reflected) was playing found zero error between displayed values and
the original fixed-gain formula. Its unclipped mapped p95 was 1.045 and maximum
1.129, demonstrating headroom that the earlier CSV could not represent.

The unclipped The Expert replay (`Box1VUComparison_20260908_223323_519`) has
2132 Rainmeter frames across 91 observed seconds: linked median 0.944, unclipped
p95 1.207, maximum 1.338, and 41.0% effectively pinned under fixed gain. All
displayed values still exactly match the old baseline equation. The auxiliary
Box1 raw log is incomplete: TelemetryManager restarted the Box1 collector for
a stale heartbeat at 22:34:49, so no completion marker was written. This event
does not invalidate the complete HTPC/Rainmeter capture. Earlier Box1 heartbeat
restarts occurred before this task; their underlying cause is not established.

Simulate-VUAttenuation.py explores attenuation-only candidates offline against
the sustained normal and unclipped hot captures. A candidate using 20 seconds
of linked one-second medians, a sustained-high gate, upper target 0.90, and
0.15 dB/second attenuation left the normal capture unchanged. For The Expert,
its final attenuation was 2.23 dB; pinning fell from 41.0% to 11.5% over the
whole replay, and to 0.55% in its final 30 seconds. These are simulated results,
not live validation or finalized constants. The sweep also shows that a faster
rate can stop qualifying for the sustained-high gate before enough headroom is
created; controller behavior must be evaluated as a whole. No adaptive gain is
deployed. Quiet-track gain increases, source transitions, pause behavior, and
Box1 hot-material validation remain outstanding.

The completed Box1 The Expert capture (`Box1VUComparison_20260908_223854_932`)
contains 92 observed seconds: linked median 0.525, p95 0.886, 83.1% midrange,
16.7% upper range, and 0.24% effectively pinned. Both logger completion markers
were present. The identical offline attenuation candidate makes no gain change
on this capture, preserving its already useful excursions. Thus current evidence
supports retaining existing source calibration while applying a common rule to
the two unclipped envelopes; forcing a fixed gain ratio from the Black Cow
comparison is not justified. Hot Box1 replay under a deployed controller remains
to be validated. The user is still looking for an actual quiet recording.

Only these two VU files were deployed to Analog_Floating2's @Resources/VU.
Both originals were backed up and hash-verified before any deployed write in
`diagnostics/captures/VU-headroom-backup-20260908/`, with manifest.csv containing
original hashes and destination paths. Source/deployed hashes matched after
copying, followed by one targeted Analog_Floating2 refresh. The collector,
HKLM transport, fixed gain, and ballistics constants were not changed.

Rollback: verify each backup against its manifest hash, copy SignalAcquisition.inc
and Box1VUComparisonCapture.lua from that backup directory back to their exact
manifest destinations, then run Rainmeter.exe `!Refresh Analog_Floating2`.
Do not restore the earlier listening-mode collector when rolling back this
separate VU measurement change. These measurement changes remain uncommitted
while the adaptive-gain work is in progress.

## Existing signal path and implementation constraint

Windows AudioLevel computes its asymmetric RMS envelope at the audio sample
rate, multiplies by RMSGain, and clamps its returned measure to 0..1.
[Official AudioLevel source](https://github.com/rainmeter/rainmeter/blob/v4.5.26.3894/Plugins/PluginAudioLevel/PluginAudioLevel.cpp#L778)
confirms that the current WindowsRaw fields are already smoothed, gained, and
clipped; they are not raw audio samples. Saturated captures cannot reconstruct
how far the underlying envelope exceeded full scale.

Box1 computes the matching power-domain envelope in its continuous collector,
publishes it through the repaired HKLM transport, and applies gain/clamp in
Rainmeter. Box1 raw RMS and peak telemetry are available separately.

Any shared gain stage must consume unclipped envelopes and apply one multiplier
to both channels before the final clamp. A unity-gain AudioLevel output followed
by the existing 2.7 multiplier is mathematically equivalent to the present path
and would expose the needed Windows headroom. Moving the high-rate ballistics
into a skin-frame Lua loop would change the reference motion; it is not justified
by this request or these data. Whether slow sensitivity is applied around the
existing equivalent envelopes or inside a common engine must be validated,
not treated as exactly interchangeable while gain is changing.

## Diagnostic scope and failure behavior

Capture-VUProgram.ps1 is invoked manually by Codex with a bounded 10–300 second
duration. Optional ExpectedSource / ExpectedTitle verify denon_status.txt and
Now Playing metadata before starting; WaitForMatchSeconds can arm a bounded
wait of up to 180 seconds. A timeout does not start a capture. It invokes the existing Start/Stop-Box1VUComparisonCapture scripts,
records selected Now Playing fields into the capture's track-context.log once
per second, and calls Stop in finally. It writes only Git-ignored diagnostic
files; this wrapper does not edit production collector or skin files. Failed metadata reads
are logged without interrupting production telemetry. Existing Start/Stop
timeouts and completion markers remain in force. Parser validation passed.
No production deployment or rollback is needed for the analysis tools themselves;
an active capture can be stopped with Stop-Box1VUComparisonCapture.ps1.

## Remaining validation

Characterize sustained normal, quiet, and hot examples on both paths, plus
pause/resume and a large level transition. Choose and replay candidate bounded,
linked controllers against those captures. Verify silence does not accumulate
gain, single peaks do not force attenuation, and L/R ratios survive below the
final physical display limit. Only then deploy with backups and perform the
requested user-visible checks on both sources.
