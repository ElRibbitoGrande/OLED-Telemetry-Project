; Shared presentation gating and normalized display measures.
; Requires DashboardState.inc and the selected meter response variables.

[DashboardVUDisplayLeft]
Measure=Calc
Formula=(DashboardBox1Usable ? Clamp(DashboardBox1LeftLevel * #DashboardVUGain#, 0, 1) : (DashboardVURawLeft * DashboardLevelSourceCode))
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

[DashboardVUDisplayRight]
Measure=Calc
Formula=(DashboardBox1Usable ? Clamp(DashboardBox1RightLevel * #DashboardVUGain#, 0, 1) : (DashboardVURawRight * DashboardLevelSourceCode))
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1
