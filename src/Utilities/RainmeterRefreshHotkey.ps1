[CmdletBinding()]
param(
    [string]$RainmeterExecutable = 'C:\Program Files\Rainmeter\Rainmeter.exe',
    [string]$LogPath = 'C:\RainmeterDenon\Logs\RainmeterRefreshHotkey.log',
    [string]$ArtworkDiagnosticScript = 'C:\RainmeterDenon\Utilities\ArtworkDiagnosticCapture.ps1'
)

$ErrorActionPreference = 'Stop'
$script:MaximumLogBytes = 256KB
$script:RefreshHotkeyId = 0x4B32
$script:DiagnosticHotkeyId = 0x4B31
$script:Modifiers = [uint32](0x0001 -bor 0x0002 -bor 0x4000) # ALT | CONTROL | NOREPEAT
$script:RefreshVirtualKey = [uint32]0x7A # F11
$script:DiagnosticVirtualKey = [uint32]0x79 # F10
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
        public uint Private;
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

function Invoke-ArtworkDiagnosticCapture {
    Write-HotkeyLog "ARTWORK_DIAGNOSTIC_CAPTURE requested. Script=$ArtworkDiagnosticScript"
    try {
        if (-not (Test-Path -LiteralPath $ArtworkDiagnosticScript -PathType Leaf)) {
            throw "Artwork diagnostic script not found: $ArtworkDiagnosticScript"
        }
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'powershell.exe'
        $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ArtworkDiagnosticScript
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $process = [Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) { throw 'Artwork diagnostic process invocation returned no process object.' }
        Write-HotkeyLog "ARTWORK_DIAGNOSTIC_CAPTURE started. PID=$($process.Id)"
        $process.Dispose()
    }
    catch {
        Write-HotkeyLog "ARTWORK_DIAGNOSTIC_CAPTURE error. Exception=$($_.Exception.Message)"
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

$refreshRegistered = $false
$diagnosticRegistered = $false
try {
    $refreshRegistered = [RainmeterDenon.RefreshHotkey.NativeMethods]::RegisterHotKey(
        [IntPtr]::Zero,
        $script:RefreshHotkeyId,
        $script:Modifiers,
        $script:RefreshVirtualKey
    )

    if (-not $refreshRegistered) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $errorMessage = [ComponentModel.Win32Exception]::new($errorCode).Message
        Write-HotkeyLog ((
            'Registration failure. Hotkey=Ctrl+Alt+F11 Modifiers=0x{0:X4} ' +
            'VirtualKey=0x{1:X2} Win32Error={2} Exception={3}'
        ) -f $script:Modifiers, $script:RefreshVirtualKey, $errorCode, $errorMessage)
        exit 1
    }

    $diagnosticRegistered = [RainmeterDenon.RefreshHotkey.NativeMethods]::RegisterHotKey(
        [IntPtr]::Zero,
        $script:DiagnosticHotkeyId,
        $script:Modifiers,
        $script:DiagnosticVirtualKey
    )
    if (-not $diagnosticRegistered) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $errorMessage = [ComponentModel.Win32Exception]::new($errorCode).Message
        Write-HotkeyLog ((
            'Registration failure. Hotkey=Ctrl+Alt+F10 Modifiers=0x{0:X4} ' +
            'VirtualKey=0x{1:X2} Win32Error={2} Exception={3}'
        ) -f $script:Modifiers, $script:DiagnosticVirtualKey, $errorCode, $errorMessage)
    }

    $threadId = [RainmeterDenon.RefreshHotkey.NativeMethods]::GetCurrentThreadId()
    Write-HotkeyLog ((
        'Listener started. PID={0} ThreadId={1} Mode=RegisterHotKey ' +
        'RefreshHotkey=Ctrl+Alt+F11 DiagnosticHotkey=Ctrl+Alt+F10 DiagnosticRegistered={2}'
    ) -f $PID, $threadId, $diagnosticRegistered)

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
            $message.WParam.ToUInt64() -eq [uint64]$script:RefreshHotkeyId) {
            Invoke-RainmeterRefresh
        }
        elseif ($message.Id -eq $script:WmHotkey -and
            $message.WParam.ToUInt64() -eq [uint64]$script:DiagnosticHotkeyId) {
            Invoke-ArtworkDiagnosticCapture
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
    if ($diagnosticRegistered) {
        [void][RainmeterDenon.RefreshHotkey.NativeMethods]::UnregisterHotKey(
            [IntPtr]::Zero,
            $script:DiagnosticHotkeyId
        )
    }
    if ($refreshRegistered) {
        [void][RainmeterDenon.RefreshHotkey.NativeMethods]::UnregisterHotKey(
            [IntPtr]::Zero,
            $script:RefreshHotkeyId
        )
    }
    Write-HotkeyLog "Listener stopped. PID=$PID"
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
