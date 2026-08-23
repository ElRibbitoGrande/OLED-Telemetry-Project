# Rainmeter refresh hotkey

`src\Utilities\RainmeterRefreshHotkey.ps1` registers the global Windows hotkey
Ctrl+Alt+F11 and invokes:

```text
C:\Program Files\Rainmeter\Rainmeter.exe !RefreshApp
```

The listener uses `RegisterHotKey` with `MOD_ALT | MOD_CONTROL |
MOD_NOREPEAT` and virtual key `VK_F11`. A blocking `GetMessage` loop keeps
idle CPU use negligible. A named mutex prevents duplicate listeners.
Ctrl+Alt+F11 was verified as available on the production system with a
temporary `RegisterHotKey` registration before this chord was selected.

TelemetryManager launches and supervises the deployed script at
`C:\RainmeterDenon\Utilities\RainmeterRefreshHotkey.ps1`.
`StopTelemetry.cmd` and `RestartTelemetry.cmd` include the listener through
the exact script-path lifecycle controller. Windows releases the registered hotkey if the
process is forcibly terminated; normal message-loop shutdown also calls
`UnregisterHotKey` explicitly.

Lifecycle and invocation events are written to
`C:\RainmeterDenon\Logs\RainmeterRefreshHotkey.log`. The log rotates at
256 KB and retains one archive.

The existing PowerToys Select Media remap remains responsible only for
emitting Ctrl+Alt+F11. No Rainmeter skin or PowerToys configuration is part
of this utility.
