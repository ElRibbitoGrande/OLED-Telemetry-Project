; Shared presentation gating and normalized display measures.
; Requires DashboardState.inc and the selected meter response variables.

[DashboardBox1VUSmoothedLeft]
Measure=Script
ScriptFile=#@#VU\Box1VUResponse.lua
InputMeasure=DashboardBox1LeftRmsLevel
AttackMs=#DashboardVUAttack#
DecayMs=#DashboardVUDecay#
Gain=#DashboardVUGain#
UpdateMs=32
UpdateDivider=1
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

[DashboardBox1VUSmoothedRight]
Measure=Script
ScriptFile=#@#VU\Box1VUResponse.lua
InputMeasure=DashboardBox1RightRmsLevel
AttackMs=#DashboardVUAttack#
DecayMs=#DashboardVUDecay#
Gain=#DashboardVUGain#
UpdateMs=32
UpdateDivider=1
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

[DashboardVUDisplayLeft]
Measure=Calc
Formula=(DashboardBox1Usable ? DashboardBox1VUSmoothedLeft : (DashboardVURawLeft * DashboardLevelSourceCode))
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

[DashboardVUDisplayRight]
Measure=Calc
Formula=(DashboardBox1Usable ? DashboardBox1VUSmoothedRight : (DashboardVURawRight * DashboardLevelSourceCode))
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
Box1FinalLeftMeasure=DashboardBox1VUSmoothedLeft
Box1FinalRightMeasure=DashboardBox1VUSmoothedRight
Box1SequenceMeasure=DashboardRawBox1Sequence
SourceMeasure=DashboardSource
UpdateMs=32
UpdateDivider=1
Disabled=1
DynamicVariables=1
