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