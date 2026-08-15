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
