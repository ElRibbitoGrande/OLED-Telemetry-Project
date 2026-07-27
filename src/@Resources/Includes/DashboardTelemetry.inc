; Shared read-only input layer for dashboard skins.
; Requires DashboardDefaults.inc in the skin's [Variables] section.
; Keep this schema synchronized with the existing collector output contracts.
; Dashboard layouts must consume DashboardState.inc rather than these raw measures.

[DashboardDenonStateFile]
Measure=WebParser
URL=file://#DashboardInputDenonStatePath#
RegExp=(?s)Volume=([^\r\n]*).*Source=([^\r\n]*).*QuickSelect=([^\r\n]*).*QuickSelectName=([^\r\n]*).*Mode=([^\r\n]*).*VisualMode=([^\r\n]*).*VisualModeCode=([01]).*DisplayMode=([^\r\n]*).*DisplayModeCode=([0-4]).*LevelSource=([^\r\n]*).*LevelSourceCode=([01]).*InputSignal=([^\r\n]*).*SampleRate=([^\r\n]*).*SpeakerPreset=([^\r\n]*).*MultEQ=([^\r\n]*).*DynamicEQ=([^\r\n]*).*ReferenceLevelOffset=([^\r\n]*).*DynamicVolume=([^\r\n]*).*ActiveFHL=([01]).*ActiveFHR=([01]).*ActiveFL=([01]).*ActiveC=([01]).*ActiveFR=([01]).*ActiveSL=([01]).*ActiveSR=([01]).*ActiveTRL=([01]).*ActiveTRR=([01]).*ActiveSUB1=([01]).*ActiveSUB2=([01])
UpdateRate=1
DynamicVariables=1

[DashboardRawVolume]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=1
DynamicVariables=1

[DashboardRawSource]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=2
DynamicVariables=1

[DashboardRawQuickSelect]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=3
DynamicVariables=1

[DashboardRawQuickSelectName]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=4
DynamicVariables=1

[DashboardRawListeningMode]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=5
DynamicVariables=1

[DashboardRawVisualMode]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=6
DynamicVariables=1

[DashboardRawVisualModeCode]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=7
DynamicVariables=1

[DashboardRawDisplayMode]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=8
DynamicVariables=1

[DashboardRawDisplayModeCode]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=9
DynamicVariables=1

[DashboardRawLevelSource]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=10
DynamicVariables=1

[DashboardRawLevelSourceCode]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=11
DynamicVariables=1

[DashboardRawInputSignal]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=12
DynamicVariables=1

[DashboardRawSampleRate]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=13
DynamicVariables=1

[DashboardRawSpeakerPreset]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=14
DynamicVariables=1

[DashboardRawMultEQ]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=15
DynamicVariables=1

[DashboardRawDynamicEQ]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=16
DynamicVariables=1

[DashboardRawReferenceLevelOffset]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=17
DynamicVariables=1

[DashboardRawDynamicVolume]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=18
DynamicVariables=1

[DashboardRawActiveFHL]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=19
DynamicVariables=1

[DashboardRawActiveFHR]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=20
DynamicVariables=1

[DashboardRawActiveFL]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=21
DynamicVariables=1

[DashboardRawActiveC]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=22
DynamicVariables=1

[DashboardRawActiveFR]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=23
DynamicVariables=1

[DashboardRawActiveSL]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=24
DynamicVariables=1

[DashboardRawActiveSR]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=25
DynamicVariables=1

[DashboardRawActiveTRL]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=26
DynamicVariables=1

[DashboardRawActiveTRR]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=27
DynamicVariables=1

[DashboardRawActiveSUB1]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=28
DynamicVariables=1

[DashboardRawActiveSUB2]
Measure=WebParser
URL=[DashboardDenonStateFile]
StringIndex=29
DynamicVariables=1

[DashboardNowPlayingStateFile]
Measure=WebParser
URL=file://#DashboardInputNowPlayingStatePath#
RegExp=(?s)Active=([01]).*Source=([^\r\n]*).*Title=([^\r\n]*).*Artist=([^\r\n]*).*Album=([^\r\n]*).*PositionSeconds=([^\r\n]*).*DurationSeconds=([^\r\n]*).*Position=([^\r\n]*).*Duration=([^\r\n]*).*Progress=([^\r\n]*).*ArtworkAvailable=([01]).*Artwork=([^\r\n]*)
UpdateRate=1
DynamicVariables=1

[DashboardRawNowPlayingActive]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=1
DynamicVariables=1

[DashboardRawNowPlayingSource]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=2
DynamicVariables=1

[DashboardRawTitle]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=3
DynamicVariables=1

[DashboardRawArtist]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=4
DynamicVariables=1

[DashboardRawAlbum]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=5
DynamicVariables=1

[DashboardRawPositionSeconds]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=6
DynamicVariables=1

[DashboardRawDurationSeconds]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=7
DynamicVariables=1

[DashboardRawPosition]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=8
DynamicVariables=1

[DashboardRawDuration]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=9
DynamicVariables=1

[DashboardRawProgress]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=10
DynamicVariables=1

[DashboardRawArtworkAvailable]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=11
DynamicVariables=1

[DashboardRawArtwork]
Measure=WebParser
URL=[DashboardNowPlayingStateFile]
StringIndex=12
DynamicVariables=1
