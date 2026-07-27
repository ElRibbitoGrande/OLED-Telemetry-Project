; Shared left/right Windows output acquisition.
; The selected meter response supplies gain, attack, and decay variables.

[DashboardVUAudioOutput]
Measure=Plugin
Plugin=AudioLevel
Port=Output
RMSAttack=#DashboardVUAttack#
RMSDecay=#DashboardVUDecay#
RMSGain=#DashboardVUGain#
DynamicVariables=1

[DashboardVURawLeft]
Measure=Plugin
Plugin=AudioLevel
Parent=DashboardVUAudioOutput
Channel=L
Type=RMS

[DashboardVURawRight]
Measure=Plugin
Plugin=AudioLevel
Parent=DashboardVUAudioOutput
Channel=R
Type=RMS
