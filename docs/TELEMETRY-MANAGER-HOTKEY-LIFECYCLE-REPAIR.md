# TelemetryManager hotkey supervision lifecycle repair

## Captured causes

The repeated hotkey-listener launches and the TelemetryManager exits are
separate lifecycle defects.

TelemetryManager originally identified children with an unanchored regular
expression against every `powershell.exe` command line. It did not retain or
validate the process returned by `Start-Process`. It also logged `Started`
before checking whether the new process remained alive.

The captured listener log shows that the original successful listener, PID
28848, stopped appearing as a PowerShell process without writing its normal
stop record. Every later launch acquired the listener mutex, reached
`RegisterHotKey`, failed with Win32 error 1409, and exited. This is not the
listener mutex rejecting a duplicate. The current machine likewise has no
PowerShell listener while Ctrl+Alt+F12 remains unavailable to
`RegisterHotKey`. Microsoft documents F12 as reserved for debugger use, so
the key is not guaranteed to be registerable through `RegisterHotKey`:

https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-registerhotkey

The old manager therefore saw no matching persistent process, launched a new
short-lived process every cycle, and reported each attempt as a successful
start. A status sample could catch one of those transient PIDs and incorrectly
report the listener as running.

The repair stops using F12. A direct, temporary system registration verified
that Ctrl+Alt+F11 had no conflict, after which it was immediately
unregistered. The listener therefore registers Ctrl+Alt+F11 (`VK_F11`) and
retains the simple `RegisterHotKey` plus blocking `GetMessage` architecture.
There is no keyboard-hook fallback. A registration failure is logged and the
listener exits so the manager can retry at its bounded interval.

TelemetryManager termination had a different cause. The entire infinite loop
was protected by `try/finally` but no `catch`, while
`$ErrorActionPreference = 'Stop'`. Any terminating error in process queries,
freshness reads, logging, process launch, or the direct status-file overwrite
left the loop and executed the `Telemetry Manager stopped` line in `finally`.
The old log did not record the exception, so the precise August 21 throwing
call is not recoverable. The last status was written at 18:04:09, the final
listener attempt was logged at 18:04:12, and shutdown followed at 18:04:14,
which places the failure in the remaining supervision/status portion of that
cycle. An exclusive reader against `telemetry_manager_status.txt` reproduces
an `IOException` in the old direct `WriteAllLines` call and reproduces the
termination mechanism. The stale status file was a consequence of that
unhandled exit.

## Narrow correction

- `TelemetryProcessIdentity.ps1` recognizes only a Windows PowerShell process
  whose command line begins with the expected production flags and exact
  `-File` path. Inspection commands that merely contain a script name do not
  match.
- The manager retains and verifies the launched listener PID after one second.
  A healthy existing listener is logged only when first recognized. An
  immediate exit records its PID and exit code, then retries no more than once
  per minute in production.
- If two exact listeners overlap, the oldest is preserved and the newer copy
  is terminated.
- `RainmeterRefreshHotkey.ps1` corrects the native `MSG` layout and registers
  Ctrl+Alt+F11 through `RegisterHotKey`; it does not install a keyboard hook.
- Process-query, collector, listener, freshness, logging, and state-publication
  failures are contained and throttled. A failed cycle continues to the next
  cycle rather than leaving the manager.
- Status publication uses a same-directory temporary file, replacement, three
  bounded attempts, and nonfatal failure handling. Normal manager exit writes
  `Manager=Stopped`.
- `TelemetryProcessControl.ps1` replaces the unsafe command-line regexes in
  `StopTelemetry.cmd` and `RestartTelemetry.cmd`. It stops only exact script
  identities, stops the manager first, waits at most five seconds, records a
  stopped status, and refuses a restart if any exact telemetry PID remains.

## Callers and file access

`LaunchTelemetryManager.vbs` is the persistent manager launcher.
`RestartTelemetry.cmd` and `StopTelemetry.cmd` call
`TelemetryProcessControl.ps1`. The manager launches the Denon collector,
NowPlayingRouter, DecoderCollector, Box1Collector, and refresh listener. The
router continues to own Apple Music/WiiM collector selection.

The manager reads the local process table, child script existence, and the
timestamps of `denon_heartbeat.txt`, `decoder_heartbeat.txt`,
`box1_heartbeat.txt`, `NowPlaying\router_heartbeat.txt`, and
`NowPlaying\now_playing.txt`. It writes only `telemetry_manager.log`,
`telemetry_manager_status.txt`, and its short-lived status temp file. No
collector network, retry, routing, metadata, artwork, VU, or display behavior
is changed.

Local CIM operations have a three-second operation timeout. Listener startup
verification is one second. Production listener retry is sixty seconds.
Status replacement retries three times with 100 ms spacing. Stop/restart wait
is bounded at five seconds. Network timeouts remain owned by the independent
collector processes, so one failed collector cannot block unrelated display
elements through this change.

## Deployment and rollback

Deploy only these runtime files after backing up their deployed predecessors:

- `TelemetryManager.ps1`
- `TelemetryProcessControl.ps1`
- `Utilities\TelemetryProcessIdentity.ps1`
- `StopTelemetry.cmd`
- `RestartTelemetry.cmd`
- `Utilities\RainmeterRefreshHotkey.ps1`

Restart with the deployed `RestartTelemetry.cmd`. Do not refresh Rainmeter.

Rollback by running `StopTelemetry.cmd`, restoring the six backed-up files
(removing the two newly added files if the previous version had none), and
starting the restored `RestartTelemetry.cmd`. Verify repository/deployed
SHA-256 equality in either direction before restart.
