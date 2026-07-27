; AF2-owned production-style VU geometry. Coordinates are explicit so no
; inherited scale variable can displace a rotator outside the VU region.

[AF2VUFaceStyle]
ImageName=#@#Images\analog\Analog_Floating.png
W=336
H=202
PreserveAspectRatio=1
AntiAlias=1
ImageTint=255,252,238,255
ColorMatrix1=1.85;0;0;0;0
ColorMatrix2=0;1.85;0;0;0
ColorMatrix3=0;0;1.65;0;0
ColorMatrix4=0;0;0;1;0
ColorMatrix5=0.035;0.025;0.005;0;1

[AF2VUNeedleStyle]
ImageName=#@#Images\AnalogFloating2\VU_Needle.png
W=14
H=134
OffsetX=10
OffsetY=132
StartAngle=11.5
RotationAngle=2.1
AntiAlias=1
ImageTint=255,248,190,255
ColorMatrix1=1.8;0;0;0;0
ColorMatrix2=0;1.8;0;0;0
ColorMatrix3=0;0;1.45;0;0
ColorMatrix4=0;0;0;1;0
ColorMatrix5=0.04;0.025;0;0;1

[AF2VUShadowStyle]
ImageName=#@#Images\AnalogFloating2\VU_Needle.png
W=14
H=134
OffsetX=10
OffsetY=132
StartAngle=11.5
RotationAngle=2.1
ImageTint=235,178,62,175
AntiAlias=1
