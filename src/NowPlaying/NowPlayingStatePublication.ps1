$script:NowPlayingPublicationMutexName = 'Local\RainmeterDenonNowPlayingStatePublication'
$script:NowPlayingPublicationRetryDelaysMilliseconds = @(25, 50, 100, 150, 200)

if (-not ('RainmeterDenon.NowPlayingNativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace RainmeterDenon
{
    public static class NowPlayingNativeMethods
    {
        [DllImport(
            "kernel32.dll",
            EntryPoint = "ReplaceFileW",
            CharSet = CharSet.Unicode,
            ExactSpelling = true,
            SetLastError = true
        )]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ReplaceFileW(
            string replacedFileName,
            string replacementFileName,
            IntPtr backupFileName,
            uint replaceFlags,
            IntPtr exclude,
            IntPtr reserved
        );
    }
}
'@
}

function Write-NowPlayingPublicationRetry {
    param(
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Attempt,
        [Parameter(Mandatory)][int]$MaximumAttempts,
        [Parameter(Mandatory)][int]$DelayMilliseconds,
        [Parameter(Mandatory)][int]$NativeErrorCode,
        [Parameter(Mandatory)][string]$NativeErrorMessage,
        [hashtable]$DiagnosticFields = @{}
    )

    try {
        if (-not (Get-Command Write-NowPlayingDiagnostic -ErrorAction SilentlyContinue)) { return }

        $fields = @{
            statePath = $Path
            stateWrite = 'retry'
            attempt = $Attempt
            maximumAttempts = $MaximumAttempts
            retryDelayMilliseconds = $DelayMilliseconds
            win32Error = $NativeErrorCode
            exception = $NativeErrorMessage
        }
        foreach ($key in $DiagnosticFields.Keys) { $fields[$key] = $DiagnosticFields[$key] }

        Write-NowPlayingDiagnostic -Component $Component -Event 'STATE_WRITE_RETRY' -Fields $fields
    }
    catch {
        # Retry diagnostics are best-effort and cannot affect publication.
    }
}

function Write-NowPlayingStateFile {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Content')][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory, ParameterSetName = 'Lines')][AllowEmptyCollection()][string[]]$Lines,
        [Parameter(Mandatory)][string]$Component,
        [hashtable]$DiagnosticFields = @{}
    )

    $directory = Split-Path -Parent $Path
    $leafName = [IO.Path]::GetFileName($Path)
    $temporaryPath = Join-Path $directory ('{0}.{1}.{2}.tmp' -f $leafName, $PID, [Guid]::NewGuid().ToString('N'))
    $mutex = $null
    $lockTaken = $false

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Lines') {
            [IO.File]::WriteAllLines($temporaryPath, $Lines, [Text.UTF8Encoding]::new($false))
        }
        else {
            [IO.File]::WriteAllText($temporaryPath, $Content, [Text.UTF8Encoding]::new($false))
        }

        $mutex = [Threading.Mutex]::new($false, $script:NowPlayingPublicationMutexName)
        try {
            $lockTaken = $mutex.WaitOne(2000)
        }
        catch [Threading.AbandonedMutexException] {
            $lockTaken = $true
        }

        if (-not $lockTaken) {
            throw [TimeoutException]::new(
                "Timed out waiting for the shared Now Playing state publication mutex."
            )
        }

        $maximumAttempts = $script:NowPlayingPublicationRetryDelaysMilliseconds.Count + 1
        for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
            if (-not [IO.File]::Exists($Path)) {
                [IO.File]::Move($temporaryPath, $Path)
                return
            }

            $replaceSucceeded = [RainmeterDenon.NowPlayingNativeMethods]::ReplaceFileW(
                $Path,
                $temporaryPath,
                [IntPtr]::Zero,
                [uint32]0,
                [IntPtr]::Zero,
                [IntPtr]::Zero
            )

            if ($replaceSucceeded) { return }

            $nativeErrorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $nativeError = [ComponentModel.Win32Exception]::new($nativeErrorCode)
            $transientError = $nativeErrorCode -in @(5, 32, 33, 1175)

            if (-not $transientError -or $attempt -ge $maximumAttempts) {
                $failureMessage = (
                    "ReplaceFileW failed replacing '{0}' with '{1}' " +
                    "on attempt {2} of {3} (Win32 error {4}: {5})"
                ) -f @(
                    $Path,
                    $temporaryPath,
                    $attempt,
                    $maximumAttempts,
                    $nativeErrorCode,
                    $nativeError.Message
                )
                throw [ComponentModel.Win32Exception]::new(
                    $nativeErrorCode,
                    $failureMessage
                )
            }

            $delayMilliseconds = $script:NowPlayingPublicationRetryDelaysMilliseconds[$attempt - 1]
            Write-NowPlayingPublicationRetry `
                -Component $Component `
                -Path $Path `
                -Attempt $attempt `
                -MaximumAttempts $maximumAttempts `
                -DelayMilliseconds $delayMilliseconds `
                -NativeErrorCode $nativeErrorCode `
                -NativeErrorMessage $nativeError.Message `
                -DiagnosticFields $DiagnosticFields
            Start-Sleep -Milliseconds $delayMilliseconds
        }
    }
    finally {
        if ($lockTaken -and $null -ne $mutex) {
            try { $mutex.ReleaseMutex() } catch {}
        }
        if ($null -ne $mutex) { $mutex.Dispose() }
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}
