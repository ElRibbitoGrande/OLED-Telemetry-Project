; Shared left/right Windows output acquisition.
; The selected meter response supplies gain, attack, and decay variables.

[DashboardVUAudioOutput]
Measure=Plugin
Plugin=AudioLevel
Port=Output
RMSAttack=#DashboardVUAttack#
RMSDecay=#DashboardVUDecay#
; Preserve headroom for measurement and the shared sensitivity stage.
; The compatibility measures below apply the existing gain and final clamp.
RMSGain=1
DynamicVariables=1

[DashboardVUEnvelopeLeft]
Measure=Plugin
Plugin=AudioLevel
Parent=DashboardVUAudioOutput
Channel=L
Type=RMS

[DashboardVUEnvelopeRight]
Measure=Plugin
Plugin=AudioLevel
Parent=DashboardVUAudioOutput
Channel=R
Type=RMS

[DashboardVURawLeft]
Measure=Calc
Formula=Clamp(DashboardVUEnvelopeLeft * #DashboardVUGain#, 0, 1)
MinValue=0
MaxValue=1
DynamicVariables=1

[DashboardVURawRight]
Measure=Calc
Formula=Clamp(DashboardVUEnvelopeRight * #DashboardVUGain#, 0, 1)
MinValue=0
MaxValue=1
DynamicVariables=1
