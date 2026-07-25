WScript.Sleep 25000

Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\RainmeterDenon\denon_status.ps1""", 0, False
Set WshShell = Nothing
