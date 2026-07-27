; Complete layout-facing presentation contract shared by dashboard layouts.
; DashboardTelemetry.inc must be included before this file.
; Layouts must not consume DashboardRaw* measures directly.

[DashboardDisplayModeCode]
Measure=Calc
Formula=DashboardRawDisplayModeCode
DynamicVariables=1

[DashboardLevelSourceCode]
Measure=Calc
Formula=DashboardRawLevelSourceCode
DynamicVariables=1

[DashboardSource]
Measure=String
String=[DashboardRawSource]
DynamicVariables=1

[DashboardAudioFormat]
Measure=String
String=[DashboardRawInputSignal]
DynamicVariables=1

[DashboardVolumeRelativeDb]
Measure=String
String=[DashboardRawVolume]
DynamicVariables=1

[DashboardVolumeAbsolute]
Measure=Calc
Formula=DashboardRawVolume + 80
DynamicVariables=1

[DashboardListeningMode]
Measure=String
String=[DashboardRawListeningMode]
DynamicVariables=1

[DashboardQuickSelectNumber]
Measure=String
String=[DashboardRawQuickSelect]
DynamicVariables=1

[DashboardQuickSelectName]
Measure=String
String=[DashboardRawQuickSelectName]
DynamicVariables=1

[DashboardReferenceLevelOffset]
Measure=String
String=[DashboardRawReferenceLevelOffset]
DynamicVariables=1

[DashboardMultEQ]
Measure=String
String=[DashboardRawMultEQ]
DynamicVariables=1

[DashboardArtwork]
Measure=String
String=[DashboardRawArtwork]
DynamicVariables=1

[DashboardNowPlayingActive]
Measure=Calc
Formula=DashboardRawNowPlayingActive
DynamicVariables=1

[DashboardNowPlayingService]
Measure=String
String=[DashboardRawNowPlayingSource]
DynamicVariables=1

[DashboardNowPlayingTitle]
Measure=String
String=[DashboardRawTitle]
DynamicVariables=1

[DashboardNowPlayingArtist]
Measure=String
String=[DashboardRawArtist]
DynamicVariables=1

[DashboardNowPlayingAlbum]
Measure=String
String=[DashboardRawAlbum]
DynamicVariables=1

[DashboardNowPlayingPositionSeconds]
Measure=Calc
Formula=DashboardRawPositionSeconds
DynamicVariables=1

[DashboardNowPlayingDurationSeconds]
Measure=Calc
Formula=DashboardRawDurationSeconds
DynamicVariables=1

[DashboardNowPlayingPosition]
Measure=String
String=[DashboardRawPosition]
DynamicVariables=1

[DashboardNowPlayingDuration]
Measure=String
String=[DashboardRawDuration]
DynamicVariables=1

[DashboardNowPlayingProgress]
Measure=Calc
Formula=DashboardRawProgress
MinValue=0
MaxValue=100
DynamicVariables=1

[DashboardNowPlayingArtworkAvailable]
Measure=Calc
Formula=DashboardRawArtworkAvailable
DynamicVariables=1

[DashboardConfiguredSpeakerLayout]
Measure=String
String=#ConfiguredSpeakerLayoutValue#
DynamicVariables=1

; Authoritative current AVR output-channel state from a completed CV? response.
[DashboardActiveFHL]
Measure=Calc
Formula=DashboardRawActiveFHL
DynamicVariables=1

[DashboardActiveFHR]
Measure=Calc
Formula=DashboardRawActiveFHR
DynamicVariables=1

[DashboardActiveFL]
Measure=Calc
Formula=DashboardRawActiveFL
DynamicVariables=1

[DashboardActiveC]
Measure=Calc
Formula=DashboardRawActiveC
DynamicVariables=1

[DashboardActiveFR]
Measure=Calc
Formula=DashboardRawActiveFR
DynamicVariables=1

[DashboardActiveSL]
Measure=Calc
Formula=DashboardRawActiveSL
DynamicVariables=1

[DashboardActiveSR]
Measure=Calc
Formula=DashboardRawActiveSR
DynamicVariables=1

[DashboardActiveTRL]
Measure=Calc
Formula=DashboardRawActiveTRL
DynamicVariables=1

[DashboardActiveTRR]
Measure=Calc
Formula=DashboardRawActiveTRR
DynamicVariables=1

[DashboardActiveSUB1]
Measure=Calc
Formula=DashboardRawActiveSUB1
DynamicVariables=1

[DashboardActiveSUB2]
Measure=Calc
Formula=DashboardRawActiveSUB2
DynamicVariables=1

; Numeric value:
;   0=None, 1=Dolby Atmos, 2=DTS:X, 3=Schiit,
;   4=Apple Music, 5=Plex, 6=Windows.
; String value:
;   NONE, DOLBY_ATMOS, DTS_X, SCHIIT, APPLE_MUSIC, PLEX, WINDOWS.
[DashboardLogoResolver]
Measure=Script
ScriptFile=#@#Scripts\DashboardState.lua
DynamicVariables=1

[DashboardCurrentLogoCode]
Measure=Calc
Formula=DashboardLogoResolver
DynamicVariables=1

[DashboardCurrentLogo]
Measure=String
String=[DashboardLogoResolver]
DynamicVariables=1
