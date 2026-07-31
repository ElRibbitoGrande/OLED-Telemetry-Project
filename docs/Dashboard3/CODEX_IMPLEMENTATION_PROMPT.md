# Dashboard 3 implementation task

Implement Dashboard3 in this isolated Git worktree.

Before changing code, inspect:

- `src/Dashboard3/`
- `docs/references/Dashboard3/Dashboard_3_Blueprint.png`
- `docs/references/Dashboard3/Dashboard_3_Blueprint.txt`
- existing telemetry contracts and project conventions
- relevant deployment and validation helpers

The PNG is the sole authoritative visual specification. The TXT is the authoritative
implementation decomposition. Do not generate a replacement blueprint, propose a different
layout, or reinterpret the visual design.

## Fixed product constraints

- Dedicated 2560x1600 OLED at Windows scaling 100%.
- Full edge-to-edge panel. No exterior margin, safety border, or decorative frame.
- Top row contains only Format, Listening Mode, and Source, primarily icons with minimal text.
- Now Playing is a foreground overlay on the left: album art, title, artist, album.
- Volume is a foreground circular indicator on the right.
- The analyzer is the dominant element and extends partially beneath the inner edges of
  Now Playing and Volume exactly as shown in the approved PNG.
- Do not modify Analog_Floating2.
- Work only in this worktree. Do not write to the live OneDrive Rainmeter folder.
- Rainmeter is temporary. Preserve a clean migration path to a native renderer.
- Keep 32 FFT bands during initial development unless a compelling technical reason requires more.
- Do not ask questions already answered by the repository or the two authoritative references.

## Proven baseline

The checkpointed live experiment proves:

- Rainmeter AudioLevel produces working multiband FFT data.
- Lua can read those values.
- Lua can publish dynamic Rainmeter Shape paths.
- Foreground layering for Now Playing and Volume works.
- Conventional isolated bars are visually wrong.
- A single filled polygon/blob is visually wrong.
- Hard clipping creates flat mesas.
- Excessive smoothing creates a generic symmetrical dome and destroys the irregular peaks.
- Irregular, changing peaks are an essential part of the design.

Remove obsolete experiments rather than stacking more experiments on top of them.

## Required architecture

Treat Dashboard3 as an independent renderer with temporary legacy acquisition.

### 1. Acquisition

- Raw FFT, RMS, and legacy telemetry only.
- No aesthetic weighting, geometry, glow, history, or renderer-specific logic.
- Preserve separate validity and freshness for audio, AVR, and Now Playing.

### 2. Canonical frame and scene model

- Build one coherent Dashboard3-owned frame per update.
- Only a legacy adapter may know `DashboardRaw*` measure names.
- The rest of Dashboard3 consumes semantic audio, AVR, Now Playing, health, and scene fields.
- Existing collectors and schemas remain compatible without becoming the renderer's internal API.

### 3. DSP and response shaping

- Appropriate logarithmic/perceptual frequency mapping.
- Noise floor, ceiling, static frequency correction, and normalization.
- Fast attack and slower release based on elapsed time.
- Peak hold and decay.
- Preserve irregular peaks and asymmetry.
- Do not force a centered dome.

### 4. History engine

- Fixed-size rolling history of processed spectra.
- Historical frames generate the slowly decaying temporal mesh and line structure.
- History is first-class geometry/state, not merely decorative glow.
- Bounded memory and an explicit reset path.

### 5. Base rendering

- Continuous spline-interpolated spectral landscape.
- No conventional bars.
- No opaque filled blob.
- Fine luminous historical mesh.
- Bright current spectral crest/surface.
- Renderer consumes processed semantic models, not raw Rainmeter measures.
- Prefer a small number of composite paths over per-band bangs.

### 6. Effects

Back to front:

1. Background glow
2. Dark vertically compressed reflective floor
3. Fine historical spectral mesh
4. Glowing current spectral surface / crest
5. Vertical peak-emission light streaks
6. Peak-triggered particles drifting upward and fading

Additional requirements:

- Long vertical rays are distinct from the historical mesh.
- Particles spawn only from meaningful peaks.
- Use the reference's intensity palette:
  deep blue -> cyan -> white -> gold -> orange.
- Color communicates intensity; do not randomly assign fixed colors by frequency.
- Effects are bounded and independently disableable.
- Failure of one effect must not stop the base renderer.

### 7. Host and publishing

- `Dashboard3.ini` should become a boring host:
  timing, includes, generic meters, and output bindings.
- One engine entry point should orchestrate modules.
- Other Lua files should be modules without global entry points.
- Preserve a clean presentation adapter boundary so Rainmeter can later be removed.

## Failure isolation

- Audio failure fades the analyzer to rest while telemetry continues.
- AVR failure marks only AVR data stale.
- Now Playing failure affects only that overlay.
- DSP failure emits a safe rested spectrum.
- Effect failure disables only that effect.
- Do not preserve an entirely frozen last frame because one subsystem failed.

## First implementation objective

Create one coherent runnable repository version, not another disposable experiment.

First write a concise implementation plan in the task transcript. Then implement the first
architecturally coherent version that establishes:

- modular acquisition, canonical frame, DSP, history, rendering, effects, and host boundaries;
- irregular continuous live spectrum;
- slowly decaying historical mesh/lines;
- bright current crest;
- vertical peak streaks;
- restrained peak particles;
- dark reflection;
- intensity-based blue/cyan/white/gold/orange behavior;
- correct foreground layering with Now Playing and Volume.

Visual polish may be staged after the architecture works, but bars, a filled blob, or a generic
symmetrical dome are not acceptable substitutes.

## Validation and delivery

- Validate Rainmeter and Lua syntax before claiming completion.
- Add deterministic fixtures or a test mode for:
  silence, tones, sweep, music-like spectra, and missing/stale telemetry where practical.
- Add a deployment script that:
  copies only Dashboard3 to the live Rainmeter folder,
  makes a timestamped rollback backup,
  never modifies Analog_Floating2,
  and does not deploy automatically.
- Keep the worktree reviewable.
- Do not commit implementation changes unless explicitly asked.
- At completion report:
  architecture,
  changed files,
  validation performed and results,
  known limitations,
  exact manual deployment and rollback commands.
