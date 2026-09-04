# Analog_Floating2 UI and artwork stabilization

## Established baseline

The repository and deployed copies of all inspected lifecycle, collector,
shared-state, and Analog_Floating2 files matched by SHA-256 before this work.
The branch was `dashboard-3` at `c6f3619` and the worktree was clean.

`SpeakerPreset` was already collected by `denon_status.ps1`, published in
`denon_status.txt`, parsed as `DashboardRawSpeakerPreset`, and therefore did
not require another Denon request path. The display contract now exposes it as
`DashboardSpeakerPreset`.

## Artwork pipeline

1. `NowPlayingRouter.ps1` reads `denon_status.txt` and runs exactly one source
   collector: Apple Music for `HTPC`, WiiM for `LYR+`, or neither for other
   sources.
2. The active collector acquires metadata and artwork. Apple Music searches
   the iTunes catalog; WiiM supplies `albumArtURI`.
3. Artwork is downloaded to a unique temporary file, validated, and moved to
   the inactive source-specific slot. The existing advertised slot is not
   overwritten.
4. `NowPlayingStatePublication.ps1` publishes `now_playing.txt` with a shared
   mutex and `ReplaceFileW`.
5. `DashboardTelemetry.inc` parses the state file. `DashboardState.inc`
   exposes layout-facing measures.
6. `NowPlayingDiagnostic.lua` independently validates the complete artwork
   tuple, retains its last valid read through transient open failures, and
   applies only a complete, existing image to `AF2Artwork`. It explicitly
   unloads and reloads that meter on transitions and performs a targeted
   30-second reapply while artwork is active. It never calls `!RefreshApp`.

## Demonstrated defects and bounded repair

A 12-second read test against the live one-second state publisher observed 10
ordinary file-open failures in 729 attempts. The earlier Rainmeter diagnostic
converted each failure into an all-empty state, producing 16,982 false state
transitions in retained logs. The revised controller treats these as transient
and does not clear or hide the last valid artwork because of a failed read.

Two image lifecycle hazards were also present:

- WiiM replaced one constant `wiim_artwork.jpg` path, which allowed Rainmeter
  image caching or an open handle to outlive changed contents.
- Apple's in-memory A/B toggle reset on every collector start and could choose
  the slot still advertised to Rainmeter.

Apple and WiiM now both choose the slot opposite the currently advertised
image. WiiM uses metadata plus artwork URL when `trackId` is empty, so a device
that omits track IDs cannot leave old artwork indefinitely. Apple ignores the
temporary `Connecting…` metadata state, retains last-known-good artwork during
bounded backoff, and continues low-frequency recovery attempts after the old
image is no longer appropriate.

The live soak included a user-controlled pause at 16:14:48. It demonstrated a
separate Apple lifecycle behavior, not the unexplained startup failure: after
three paused polls the collector cleared valid artwork, published
`ArtworkAvailable=0` for roughly 53 seconds, and forced a redundant catalog
download on resume. Apple exposes `PlaybackStatus=Paused` on the still-valid
session, so the collector now treats `Playing` and `Paused` as display-active.
The current metadata, artwork, and slot remain visible through an ordinary
pause. `Stopped`, a closed/missing session, or a source change still hides Now
Playing. Resume no longer discards or reacquires artwork.

A naturally occurring blank-art failure was captured at
`2026-09-03T16:03:46.934-07:00`. Apple metadata was active; the shared state
advertised `artwork_b.jpg` with `ArtworkAvailable=1`; the 19,104-byte file was
a valid JPEG; its SHA-256 was
`FDC860D08BDAEB1409C434EA73673BE35F8F0C93DFFBC597970EDE4794781CD0`;
and manager, router, collector, and Rainmeter processes were alive. Rainmeter's
Lua controller also believed that exact path was applied, while the image was
visibly absent. This localizes the observed failure to Rainmeter's image
meter/render state rather than artwork acquisition or publication.

The meter had two competing authorities: `MeasureName=DashboardArtwork` and
Lua-written `ImageName`. The WebParser measure could remain invalid across a
transient state-file read even after Lua set a valid `ImageName`. The repair
removes the measure binding from only `AF2Artwork`; the validated Lua path is
now its single authority. Recovery clears and updates the one meter before
setting the validated path and updating it again, forcing release of stale
bitmap/cache state without refreshing the skin or application.

Post-capture introspection then recorded `meterHidden=1` two seconds after the
controller issued `!ShowMeter`, while the advertised, parsed, applied, and
meter `ImageName` paths all remained identical and valid. The final repair also
removes the meter's static `Hidden=1`, artwork-group membership, and the
refresh-time artwork-group hide. An empty initial `ImageName` remains visually
blank, and the Lua controller is now the sole authority for both the path and
visibility. Diagnostics record the parsed measure, controller path, and actual
meter `ImageName`/`Hidden` options separately.

## OLED pixel shifting

`Analog_Floating2` occupies a fixed 1707-by-1067 black canvas at the origin of
the dedicated OLED (physical desktop coordinates `2560,384`). The closest
visible non-background geometry has measured clearances of 22 pixels left,
45 top, 19 right, and 88 bottom, so a 3-pixel window shift cannot clip text,
artwork, VU meters, rules, or speaker icons. The deployment changes only the persisted
`[Analog_Floating2]` `KeepOnScreen` value in Rainmeter.ini from `1` to `0`,
because Rainmeter otherwise clamps negative offsets even though the visible
geometry has ample clearance. The prior value and a full config backup are
stored in the timestamped rollback folder.

`AF2PixelShift.lua` moves the complete Rainmeter skin window—not individual
meters—through nine absolute positions: neutral, the four axis directions,
and the four diagonals at 3 pixels. It advances once every 9,375 skin updates
(approximately five minutes at the 32 ms skin update interval) and returns to
neutral every 45 minutes. Initialization always moves to the known neutral
origin, so saved Rainmeter coordinates cannot accumulate drift across a skin
reload or application restart. Routine moves perform no application logging
and do not refresh Rainmeter, update meter options, or touch any telemetry or
hotkey process. Rainmeter may persist its normal window position when moved;
the initialization reset prevents that persisted offset from becoming a new
origin.

For validation only, each position can be selected with:

```powershell
& 'C:\Program Files\Rainmeter\Rainmeter.exe' `
  !CommandMeasure AF2PixelShift 'SetPosition(<1-through-9>)' Analog_Floating2
```

Return to position 1 after testing.

## Production validation observations

- The naturally occurring active-playback startup failure was captured before
  it recovered. The valid advertised file, matching hashes, healthy processes,
  and blank image meter localize that event to Rainmeter presentation; it is
  not explained by the later controlled pause.
- A ten-minute Apple soak observed five state transitions, no blank image, no
  duplicate process, and three transient direct-reader sharing violations that
  the Rainmeter controller retained through safely.
- A controlled Apple pause held `Active=1`, `PlaybackStatus=Paused`, the same
  title, `artwork_b.jpg`, 93,209-byte file, and SHA-256 across eight samples.
  Resume produced no second acquisition for that track. When the track later
  ended, the empty/stopped interval became inactive before the next track was
  acquired normally.
- The controlled Apple-to-WiiM-to-Apple test observed four real WiiM tracks
  (`Spanish Harlem`, `Hey Now`, `No Sanctuary Here`, and `Ain't No Sunshine`).
  Their artwork alternated A/B/A/B; every advertised image existed and had a
  valid, distinct size/hash, and Rainmeter applied every path. Returning to
  HTPC stopped WiiM and restored exactly one Apple collector.
- All nine pixel-shift positions reached their exact expected window
  coordinates and returned to neutral. A direct rendered-window capture
  confirmed the edge clearances above and no layout clipping or overlap.
- Two consecutive F10 activations created two observation-only packages with
  zero Rainmeter refreshes and stable process IDs. One F11 activation produced
  exactly one `!RefreshApp` invocation, did not launch Windows Media Player,
  restored artwork, and reset pixel shifting to neutral.
- All 50 PowerShell files parse, `git diff --check` passes, and all 24 isolated
  telemetry lifecycle assertions pass. `ValidateTelemetry.ps1` reports all
  production processes and changed runtime files healthy/matching; its overall
  warning is limited to the pre-existing `Analog_Floating.ini` divergence and
  two optional console-logo files outside this task.

## Diagnostic hotkey

The existing listener registers both shortcuts with `RegisterHotKey`:

- `Ctrl+Alt+F11`: unchanged emergency Rainmeter `!RefreshApp`.
- `Ctrl+Alt+F10`: observation-only artwork diagnostic capture.

`Ctrl+Alt+F10` was probed before implementation, registered successfully, and
was immediately released. Each capture is written beneath
`C:\RainmeterDenon\Diagnostics\Artwork\<timestamp>` and includes current state,
Rainmeter's last applied artwork state, both source buffer pairs, hashes and
timestamps, process inventory, manager/router health, and bounded log tails.

In PowerToys Keyboard Manager, map the desired spare physical key to the
shortcut **Ctrl + Alt + F10**. Do not alter the musical-note key mapping to
Ctrl+Alt+F11.

When artwork disappears:

1. Press the new Ctrl+Alt+F10-mapped key first.
2. Wait several seconds for the timestamped package to finish.
3. If desired, press the existing musical-note key for the manual Refresh All
   workaround.
4. Preserve the newest folder under
   `C:\RainmeterDenon\Diagnostics\Artwork` for analysis.

## Deployment and rollback

Run `deployment\Deploy-AF2ArtworkStabilization.ps1` from an elevated or normal
interactive PowerShell session with access to the runtime and skin folders.
The script preflights every source, backs up every destination beneath
`C:\RainmeterDenon\Backups\AF2-Artwork-Stabilization\<timestamp>`, copies and
hash-verifies the files, restarts telemetry through the existing command, and
refreshes only `Analog_Floating2`.

The deployment prints an exact rollback command. Rollback restores every file
from its manifest, restores only Analog_Floating2's prior `KeepOnScreen`
setting through `deployment\Rollback-AF2ArtworkStabilization.ps1`, and then
runs the existing `RestartTelemetry.cmd` followed by a targeted
`!Refresh Analog_Floating2`.
