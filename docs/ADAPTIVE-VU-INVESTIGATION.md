# Adaptive meter sensitivity — investigation in progress

The additional September 8 request authorizes slow, stereo-linked adaptive
meter gain for HTPC and Lyr+/Box1. It does not authorize replacing the pleasing
HTPC motion with a different response. Base gain remains 2.7 and attack /
decay remain 85 / 520 ms. A first attenuation-only trial is now deployed;
user-visible validation and quiet-recording gain increases remain outstanding.

## Current trial (23:16 September 8)

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
