WScript.Sleep 10000

Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """C:\Program Files\Rainmeter\Rainmeter.exe""", 0
Set WshShell = Nothing