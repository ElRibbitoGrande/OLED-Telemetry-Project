# Shared dashboard infrastructure

These files are additive and are not used by the current production
`Analog_Floating.ini`.

A future dashboard should include them in this order:

```ini
[Variables]
@include1=#@#Includes\DashboardDefaults.inc
@include2=#@#MeterStyles\AnalogFloating\Geometry.inc
@include3=#@#MeterStyles\AnalogFloating\Response.inc

@include4=#@#Includes\DashboardTelemetry.inc
@include5=#@#Includes\DashboardState.inc
@include6=#@#VU\SignalAcquisition.inc
@include7=#@#VU\MeterResponse.inc
@include8=#@#MeterStyles\AnalogFloating\Styles.inc
```

The layers are:

1. `DashboardTelemetry.inc`: read-only parsing of existing collector files.
2. `DashboardState.inc` and `DashboardState.lua`: the complete layout-facing
   presentation contract and the single-logo priority decision.
3. `VU`: shared signal acquisition and presentation gating.
4. `MeterStyles\AnalogFloating\Response.inc`: response and calibration.
5. `MeterStyles\AnalogFloating\Geometry.inc` and `Styles.inc`: artwork geometry
   belonging to the existing Analog_Floating VU artwork.
6. Dashboard INI files: layout, positioning, and meter declarations only.

Dashboard layouts must consume only `DashboardState.inc` exports. Measures
whose names begin with `DashboardRaw` are collector-wrapper implementation
details.

`DashboardConfiguredSpeakerLayout` is project configuration. It represents
the configured speaker layout and must never be labeled as active-channel
data.

The current-logo numeric contract is:

| Code | Identity |
|---:|---|
| 0 | None |
| 1 | Dolby Atmos |
| 2 | DTS:X |
| 3 | Schiit |
| 4 | Apple Music |
| 5 | Plex |
| 6 | Windows |

Plex detection is presentation-ready only. This infrastructure does not add a
Plex collector or invent Plex metadata.

## Layout-facing contract

AVR presentation:

- `DashboardSource`
- `DashboardAudioFormat`
- `DashboardDisplayModeCode`
- `DashboardLevelSourceCode`
- `DashboardVolumeRelativeDb`
- `DashboardVolumeAbsolute`
- `DashboardListeningMode`
- `DashboardQuickSelectNumber`
- `DashboardQuickSelectName`
- `DashboardReferenceLevelOffset`
- `DashboardMultEQ`
- `DashboardConfiguredSpeakerLayout`
- `DashboardCurrentLogoCode`
- `DashboardCurrentLogo`

Now Playing presentation:

- `DashboardNowPlayingActive`
- `DashboardNowPlayingService`
- `DashboardNowPlayingTitle`
- `DashboardNowPlayingArtist`
- `DashboardNowPlayingAlbum`
- `DashboardNowPlayingPositionSeconds`
- `DashboardNowPlayingDurationSeconds`
- `DashboardNowPlayingPosition`
- `DashboardNowPlayingDuration`
- `DashboardNowPlayingProgress`
- `DashboardNowPlayingArtworkAvailable`
- `DashboardArtwork`

## Intentional compatibility debt

The existing collector contract supplies `DisplayModeCode`, but source-specific
console presentation can override the independent format identity. To preserve
the required Atmos and DTS:X logo priority without changing collector output,
the logo registry first uses `DisplayModeCode` and then falls back to inspecting
the already-formatted listening mode and input signal. This remaining duplicate
format interpretation should be removed when collectors eventually publish a
source-independent normalized format identity.
