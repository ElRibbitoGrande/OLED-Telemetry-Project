; Shared presentation gating and normalized display measures.
; Requires DashboardState.inc and the selected meter response variables.

[Variables]
; Provisional level alignment from paired Aja/Corea captures (~4 dB).
DashboardBox1CalibrationGain=1.6

[DashboardVUAdaptiveGain]
Measure=Script
ScriptFile=#@#VU\AdaptiveGain.lua
CoreFile=#@#VU\AdaptiveGainCore.lua
MinValue=0
MaxValue=1

[DashboardBox1VUCurrentLeft]
Measure=Calc
Formula=Clamp(DashboardRawBox1RmsEnvelopeLeft * #DashboardVUGain#, 0, 1)
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

[DashboardBox1VUCurrentRight]
Measure=Calc
Formula=Clamp(DashboardRawBox1RmsEnvelopeRight * #DashboardVUGain#, 0, 1)
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

[DashboardVUDisplayLeft]
Measure=Calc
Formula=Clamp((DashboardBox1Usable ? DashboardRawBox1RmsEnvelopeLeft * #DashboardBox1CalibrationGain# : DashboardVUEnvelopeLeft * DashboardLevelSourceCode) * #DashboardVUGain# * DashboardVUAdaptiveGain, 0, 1)
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

[DashboardVUDisplayRight]
Measure=Calc
Formula=Clamp((DashboardBox1Usable ? DashboardRawBox1RmsEnvelopeRight * #DashboardBox1CalibrationGain# : DashboardVUEnvelopeRight * DashboardLevelSourceCode) * #DashboardVUGain# * DashboardVUAdaptiveGain, 0, 1)
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

; Disabled diagnostic sampler. Start-Box1VUComparisonCapture.ps1 enables it
; temporarily without changing any production response or meter formula.
[DashboardVUComparisonCapture]
Measure=Script
ScriptFile=#@#VU\Box1VUComparisonCapture.lua
ControlFile=C:\OLED-Telemetry-Project\diagnostics\Box1VUComparison.capture
WindowsLeftMeasure=DashboardVURawLeft
WindowsRightMeasure=DashboardVURawRight
Box1LeftRmsDbMeasure=DashboardRawBox1LeftRmsDb
Box1RightRmsDbMeasure=DashboardRawBox1RightRmsDb
Box1PreLeftMeasure=DashboardBox1LeftRmsLevel
Box1PreRightMeasure=DashboardBox1RightRmsLevel
Box1FinalLeftMeasure=DashboardBox1VUCurrentLeft
Box1FinalRightMeasure=DashboardBox1VUCurrentRight
Box1SequenceMeasure=DashboardRawBox1Sequence
SourceMeasure=DashboardSource
UpdateMs=32
UpdateDivider=1
Disabled=1
DynamicVariables=1
