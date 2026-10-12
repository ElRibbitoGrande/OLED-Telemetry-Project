# Instructions for Codex

Read README.md before performing any task.

## Safety and workflow

1. Do not modify C:\RainmeterDenon directly.
2. Work only inside this repository unless explicitly authorized.
3. Do not deploy changes automatically.
4. Do not delete working behavior during cleanup or refactoring.
5. Make narrowly scoped changes.
6. Explain the suspected cause before changing code.
7. Preserve rollback points using Git commits.
8. Never globally disable TLS or certificate validation.
9. Do not commit credentials, private IP configuration, certificates,
   chat archives, logs, cached artwork, or generated telemetry state.
10. Do not assume a component is unused merely because its purpose is unclear.

## System facts

- AVR: Denon AVR-X3700H
- Speaker layout: 5.2.4
- CBL/SAT is the Peladn Windows mini-PC.
- DVD is the PlayStation 5.
- 8K is the Xbox Series X.
- The Schiit Lyr+ source uses WiiM Now Playing metadata while preserving
  applicable Denon AVR telemetry.
- The AVR does not support Video Select.
- The live installation is C:\RainmeterDenon.
- This repository is the development copy.

## Lyr+ testing and user interaction

- As of 2026-10-11, the user can listen to Lyr+ while keeping the LG/HDMI
  display on the PC, interacting with Codex, and observing/recording the OLED.
  This supersedes the former audio-only display blackout constraint.
- Do not use blind waits, require HDMI display switching, or wait for an AVR
  return to HTPC. Bounded automatic captures remain useful for instrumentation,
  but do not make the user wait blindly or run a timer.
- Exhaust instrumentation, existing captures and simulation before requesting
  one consolidated physical/perceptual comparison. Give exact source, passage
  or stimulus, recording length and visible/audible requirements.

## VU motion reference

- The user prefers the HTPC needles' quicker approach to peaks and smoother
  decay. Lyr+/Box1 should match that motion; identical configured attack/decay
  numbers alone are not evidence of a perceptual match.
- Diagnose input smoothing, delivery cadence, and the complete envelope path
  separately from slow adaptive sensitivity. Preserve the pleasing HTPC motion.
- Aja by Steely Dan and Chick Corea Trio's Trilogy are user-identified examples
  of standard dynamics. Yello's The Expert is the identified hot-track example.
- After the 1.6 Box1 calibration trial, the user found Lyr motion much better
  but still slightly behind audible music compared with HTPC Apple Music.
  Treat residual latency as unresolved; improved range is not timing acceptance.
- A 100 Hz firmware report rate does not establish RMS window duration. Separate
  per-audio-sample filtering from filtering averaged RMS reports; constant-power
  equivalence tests are not proof of musical or perceptual equivalence.
- Preserve acquisition-rate HKLM publication. Diagnostic status snapshots are
  limited to 5 Hz; startup sequence recovery takes max(registry, file). Heartbeat
  publication keeps its path present and remains liveness evidence only.
- VU-only deployment/rollback must preserve the AVR watchdog baseline. Use
  diagnostics/Deploy-VULatency.ps1 and its verified manifests, not a blanket
  rollback of unrelated telemetry files.

## Validation

For every proposed PowerShell change:

1. Run PowerShell parser validation.
2. Identify all callers of the changed function or script.
3. Identify files written or read by the changed component.
4. Check timeout, retry, and error-handling paths.
5. Confirm that one failed collector cannot freeze unrelated display elements.
6. Provide the exact deployment and rollback procedure.

## Current priority

Investigate intermittent partial display freezing before adding new features.
Do not perform a broad architectural rewrite until the current failure has
been understood and documented.

## AVR health watchdog operations

- AvrWatchdog is independently supervised; heartbeat/process presence is not authoritative freshness. Trust requires fresh per-field receives plus independent read-only verification.
- RESET AVR requires sustained failed control queries, failed bounded recovery, stale collector observations and fresh exact-model HEOS identification. Ambiguous networking failures and standby must remain silent.
- Fresh network replies cannot establish physical front-panel correctness; preserve that diagnostic limitation.
- Deploy only the explicit watchdog file manifest. Preserve unrelated VU/artwork/hotkey/pixel-shift changes. Rollback and health diagnostics are documented in docs/AVR-HEALTH-WATCHDOG.md.
