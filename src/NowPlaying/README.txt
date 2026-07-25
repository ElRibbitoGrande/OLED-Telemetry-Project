APPLE MUSIC NOW PLAYING — METADATA INTEGRATION

This build wires the confirmed Apple Music media-session metadata into the approved Analog_Floating layout. Artwork remains blank for this build; title, artist, album, time, duration, and progress are live. The entire Now Playing panel is hidden whenever Apple Music is paused, stopped, or merely open.

INSTALL
1. Stop the currently running AppleMusicCollector.ps1 window/process.
2. Copy AppleMusicCollector.ps1 and LaunchAppleMusicCollector.vbs into:
   C:\RainmeterDenon\NowPlaying\
3. Copy Analog_Floating.ini.new into the folder containing your working Analog_Floating.ini.
4. Back up the working Analog_Floating.ini.
5. Rename Analog_Floating.ini.new to Analog_Floating.ini and refresh the skin.
6. Start the collector with:
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\RainmeterDenon\NowPlaying\AppleMusicCollector.ps1"

EXPECTED
- Apple Music actively playing: panel appears with title, parsed artist/album, elapsed time, duration, and progress bar.
- Apple Music paused/stopped/open only: panel disappears.
- Artwork area remains empty until the separate artwork helper is added.

The Denon collector is not changed by this package.
