# OLED Telemetry Project

This repository contains the working source and documentation for a
2560x1600 OLED telemetry display used with a Denon AVR-X3700H.

## Current system

The live deployed installation is located at:

C:\RainmeterDenon

The copy in this repository is the development and diagnostic copy.
Do not modify the live installation directly.

## Box 1 known-good production state

As of 2026-08-15, Box 1 firmware 0.18 and the Analog_Floating2 VU
integration are confirmed production-good. The collector acquires PCM1808
telemetry at approximately 100 Hz, performs the AudioLevel-equivalent RMS
envelope continuously, and publishes its current envelope through a
machine-wide, nonvolatile registry key with a scoped ACL for synchronous
Rainmeter consumption. Rainmeter's sequence-freshness guard prevents persisted
values from being treated as live when the collector is absent.

The complete architecture, measurements, failed approaches, recovery
artifacts, and enclosure lessons are preserved in
[`docs/BOX1-VU-ENGINEERING-POSTMORTEM.md`](docs/BOX1-VU-ENGINEERING-POSTMORTEM.md).

## Major components

- PowerShell telemetry and polling scripts
- Denon AVR network/telnet telemetry
- Rainmeter display skins
- WiiM Now Playing metadata
- Plex and Windows media-source integration
- Album-art retrieval and caching
- Source, surround-mode, volume, speaker-layout, and VU-meter presentation

## Hardware and source mapping

- AVR: Denon AVR-X3700H
- Display: 2560x1600 OLED panel
- Speaker layout: 5.2.4
- CBL/SAT: Peladn Windows mini-PC
- DVD: PlayStation 5
- 8K: Xbox Series X
- Schiit Lyr+ source: supplemented by WiiM metadata

The AVR does not support Denon Video Select. Do not propose it.

## Current problem

Parts of the OLED display intermittently stop updating or become stuck.
The system may continue partially updating while one or more displayed
elements retain stale values.

The initial Codex assignment is to map the existing architecture and
identify every place where stale state, blocked polling, failed process
restart, cached output, file locking, network timeout, unhandled exception,
or Rainmeter refresh failure could leave only part of the display stuck.

Do not begin by rewriting the application. First document and reproduce
the current behavior.

The deployed AVR health watchdog now independently verifies critical Denon
state and performs bounded recovery. Its evidence limits, diagnostics,
RESET AVR criteria and verified rollback procedure are documented in
[`docs/AVR-HEALTH-WATCHDOG.md`](docs/AVR-HEALTH-WATCHDOG.md).

## Private historical material

Relevant ChatGPT conversation archives are available locally under:

docs/chat-archive

That folder is intentionally excluded from Git and must not be published.
