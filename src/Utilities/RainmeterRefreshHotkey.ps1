[CmdletBinding()]
param(
    [string]$RainmeterExecutable = 'C:\Program Files\Rainmeter\Rainmeter.exe',
    [string]$LogPath = 'C:\RainmeterDenon\Logs\RainmeterRefreshHotkey.log'
)

$ErrorActionPreference = 'Stop'
$script:MaximumLogBytes = 256KB
$script:HotkeyId = 0x4B31
$script:Modifiers = [uint32](0x0001 -bor 0x0002 -bor 0x4000) # ALT | CONTROL | NOREPEAT
$script:VirtualKey = [uint32]0x7B # F12
$script:WmHotkey = [uint32]0x0312

function Write-HotkeyLog {
    param([Parameter(Mandatory)][string]$Message)

    try {
        $directory = Split-Path -Parent $LogPath
        if (-not (Test-Path -LiteralPath $directory)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
        }

        if ((Test-Path -LiteralPath $LogPath) -and
            (Get-Item -LiteralPath $LogPath).Length -ge $script:MaximumLogBytes) {

            $archivePath = "$LogPath.1"
            if (Test-Path -LiteralPath $archivePath) {
                Remove-Item -LiteralPath $archivePath -Force
            }
            Move-Item -LiteralPath $LogPath -Destination $archivePath
        }

        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value (
            '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
        )
    }
    catch {
        # Logging must never terminate the listener.
    }
}

if (-not ('RainmeterDenon.RefreshHotkey.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace RainmeterDenon.RefreshHotkey
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Message
    {
        public IntPtr WindowHandle;
        public uint Id;
        public UIntPtr WParam;
        public IntPtr LParam;
        public uint Time;
        public Point Point;
    }

    public static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RegisterHotKey(
            IntPtr windowHandle,
            int id,
            uint modifiers,
            uint virtualKey
        );

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnregisterHotKey(IntPtr windowHandle, int id);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetMessage(
            out Message message,
            IntPtr windowHandle,
            uint minimumMessage,
            uint maximumMessage
        );

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool TranslateMessage(ref Message message);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr DispatchMessage(ref Message message);

        [DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();
    }
}
'@
}

function Invoke-RainmeterRefresh {
    Write-HotkeyLog "Refresh invocation requested. Command=$RainmeterExecutable !RefreshApp"

    try {
        if (-not (Test-Path -LiteralPath $RainmeterExecutable -PathType Leaf)) {
            throw "Rainmeter executable not found: $RainmeterExecutable"
        }

        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $RainmeterExecutable
        $startInfo.Arguments = '!RefreshApp'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden

        $process = [Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) {
            throw 'Rainmeter process invocation returned no process object.'
        }
        $process.Dispose()
    }
    catch {
        Write-HotkeyLog "Refresh invocation error. Exception=$($_.Exception.Message)"
    }
}

$createdNew = $false
$mutex = [Threading.Mutex]::new(
    $true,
    'Local\RainmeterDenonRainmeterRefreshHotkey',
    [ref]$createdNew
)

if (-not $createdNew) {
    Write-HotkeyLog 'Registration failure. Another listener instance is already active.'
    $mutex.Dispose()
    exit 0
}

$registered = $false

try {
    $registered = [RainmeterDenon.RefreshHotkey.NativeMethods]::RegisterHotKey(
        [IntPtr]::Zero,
        $script:HotkeyId,
        $script:Modifiers,
        $script:VirtualKey
    )

    if (-not $registered) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $errorMessage = [ComponentModel.Win32Exception]::new($errorCode).Message
        Write-HotkeyLog ((
            'Registration failure. Hotkey=Ctrl+Alt+F12 Modifiers=0x{0:X4} ' +
            'VirtualKey=0x{1:X2} Win32Error={2} Exception={3}'
        ) -f $script:Modifiers, $script:VirtualKey, $errorCode, $errorMessage)
        exit 1
    }

    $threadId = [RainmeterDenon.RefreshHotkey.NativeMethods]::GetCurrentThreadId()
    Write-HotkeyLog ((
        'Listener started. PID={0} ThreadId={1} Hotkey=Ctrl+Alt+F12 ' +
        'Modifiers=0x{2:X4} VirtualKey=0x{3:X2}'
    ) -f $PID, $threadId, $script:Modifiers, $script:VirtualKey)

    $message = [RainmeterDenon.RefreshHotkey.Message]::new()
    while ($true) {
        $messageResult = [RainmeterDenon.RefreshHotkey.NativeMethods]::GetMessage(
            [ref]$message,
            [IntPtr]::Zero,
            0,
            0
        )

        if ($messageResult -eq -1) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw [ComponentModel.Win32Exception]::new($errorCode)
        }
        if ($messageResult -eq 0) { break }

        if ($message.Id -eq $script:WmHotkey -and
            $message.WParam.ToUInt64() -eq [uint64]$script:HotkeyId) {
            Invoke-RainmeterRefresh
        }

        [void][RainmeterDenon.RefreshHotkey.NativeMethods]::TranslateMessage([ref]$message)
        [void][RainmeterDenon.RefreshHotkey.NativeMethods]::DispatchMessage([ref]$message)
    }
}
catch {
    Write-HotkeyLog "Registration failure. Listener terminated unexpectedly. Exception=$($_.Exception.Message)"
    exit 1
}
finally {
    if ($registered) {
        [void][RainmeterDenon.RefreshHotkey.NativeMethods]::UnregisterHotKey(
            [IntPtr]::Zero,
            $script:HotkeyId
        )
    }
    Write-HotkeyLog "Listener stopped. PID=$PID"
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
