;==================================================
; DASHBOARD 3 FFT / SPECTRUM ACQUISITION
;==================================================

[MeasureAudioSpectrum]
Measure=Plugin
Plugin=AudioLevel
Port=Output
FFTSize=4096
FFTOverlap=2048
FFTAttack=50
FFTDecay=250
Bands=32
FreqMin=40
FreqMax=16000
Sensitivity=35