; Shared presentation gating and normalized display measures.
; Requires DashboardState.inc and the selected meter response variables.

[DashboardBox1VUSmoothedLeft]
Measure=Calc
Formula=Clamp(DashboardBox1LeftLevel * #DashboardVUGain#, 0, 1)
AverageSize=3
MinValue=#DashboardVUCalibrationMin#
MaxValue=#DashboardVUCalibrationMax#
DynamicVariables=1

[DashboardBox1VUSmoothedRight]
Measure=Calc
Formula=Clamp(DashboardBox1RightLevel * #DashboardVUGain#, 0, 1)
AverageSize=3
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
