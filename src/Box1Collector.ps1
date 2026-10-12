param(
    [AllowEmptyString()]
    [string]$PortName = ''
)

$ErrorActionPreference = 'Stop'

$Root = 'C:\RainmeterDenon'
$StateFile = Join-Path $Root 'box1_status.txt'
$StateTempFile = Join-Path $Root 'box1_status.tmp'
$HeartbeatFile = Join-Path $Root 'box1_heartbeat.txt'
$HeartbeatTempFile = Join-Path $Root 'box1_heartbeat.tmp'
$ErrorFile = Join-Path $Root 'box1_status_error.txt'
$ErrorTempFile = Join-Path $Root 'box1_status_error.tmp'

$BaudRate = 115200
$ReadTimeoutMilliseconds = 750
$ValidationTimeoutSeconds = 6
$ReconnectDelaySeconds = 2
$HeartbeatIntervalSeconds = 2
$PublisherShutdownTimeoutSeconds = 5
$DiagnosticShutdownTimeoutSeconds = 5
$SerialReadBufferBytes = 65536
$DiagnosticControlFile = 'C:\OLED-Telemetry-Project\diagnostics\Box1VUComparison.capture'
$DiagnosticCaptureRoot = 'C:\OLED-Telemetry-Project\diagnostics\captures'
$DiagnosticControlEventName = 'Local\RainmeterDenonBox1VUComparisonControl'
$RuntimeRegistrySubKey = 'Software\OLED-Telemetry-Project\Box1Runtime'
$RmsAttackMilliseconds = 85.0
$RmsDecayMilliseconds = 520.0
$FirmwareBannerPattern = '^BOX1 (?<Version>[0-9]+(?:\.[0-9]+)+)$'
$ExpectedReadyLine = 'TELEMETRY READY'
$PicoCdcPnpPattern = '(?i)^USB\\VID_2E8A&PID_0009&MI_00\\'
$InvariantCulture = [Globalization.CultureInfo]::InvariantCulture

# A telemetry record is accepted only when the complete line matches this shape.
$NumberPattern = '[-+]?(?:\d+(?:\.\d*)?|\.\d+)'
$TelemetryPattern = ('^L rms=({0}) peak=({0}) vu=({0}) \| R rms=({0}) peak=({0}) vu=({0})$' -f $NumberPattern)

New-Item -ItemType Directory -Path $Root -Force | Out-Null

$createdNew = $false
$singleInstanceMutex = [Threading.Mutex]::new(
    $true,
    'Local\RainmeterDenonBox1Collector',
    [ref]$createdNew
)
if (-not $createdNew) {
    $singleInstanceMutex.Dispose()
    exit 0
}

function Write-AtomicText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$TempPath,
        [Parameter(Mandatory)][string]$Content
    )

    [IO.File]::WriteAllText($TempPath, $Content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $TempPath -Destination $Path -Force
}

function Write-CollectorError {
    param([Parameter(Mandatory)][string]$Message)

    $content = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    Write-AtomicText -Path $ErrorFile -TempPath $ErrorTempFile -Content $content
}

function Clear-CollectorError {
    Remove-Item -LiteralPath $ErrorFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ErrorTempFile -Force -ErrorAction SilentlyContinue
}

function Get-InitialSequence {
    $initial = 0L
    # The diagnostic file is deliberately slower than live registry publication.
    # Preserve monotonic sequencing across restarts from either persisted copy.
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
        $key = $baseKey.OpenSubKey($RuntimeRegistrySubKey)
        try { if($key){$value=0L;if([long]::TryParse([string]$key.GetValue('Sequence'),[ref]$value)){$initial=[Math]::Max($initial,$value)}} }
        finally {if($key){$key.Dispose()};$baseKey.Dispose()}
    } catch {}
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) { return $initial }

    try {
        foreach ($line in Get-Content -LiteralPath $StateFile -ErrorAction Stop) {
            if ($line -match '^Sequence=(\d+)$') {
                return [Math]::Max($initial,[long]::Parse($Matches[1], $InvariantCulture))
            }
        }
    }
    catch {}

    return $initial
}

function Get-CandidatePortNames {
    if (-not [string]::IsNullOrWhiteSpace($PortName)) {
        $explicitPort = $PortName.Trim().ToUpperInvariant()
        if ($explicitPort -notmatch '^COM\d+$') {
            throw "PortName must use the form COM3. Received: '$PortName'."
        }
        return @($explicitPort)
    }

    try {
        return @(
            Get-CimInstance Win32_SerialPort -ErrorAction Stop |
                Where-Object {
                    $_.DeviceID -match '^COM\d+$' -and
                    $_.PNPDeviceID -match $PicoCdcPnpPattern
                } |
                Select-Object -ExpandProperty DeviceID -Unique |
                Sort-Object
        )
    }
    catch {
        throw "Could not enumerate Pico CDC serial devices. Use -PortName to specify the port. $($_.Exception.Message)"
    }
}

function New-Box1SerialPort {
    param([Parameter(Mandatory)][string]$Name)

    $serialPort = [IO.Ports.SerialPort]::new(
        $Name,
        $BaudRate,
        [IO.Ports.Parity]::None,
        8,
        [IO.Ports.StopBits]::One
    )
    $serialPort.Handshake = [IO.Ports.Handshake]::None
    $serialPort.ReadTimeout = $ReadTimeoutMilliseconds
    $serialPort.WriteTimeout = $ReadTimeoutMilliseconds
    $serialPort.ReadBufferSize = $SerialReadBufferBytes
    $serialPort.NewLine = "`n"
    $serialPort.DtrEnable = $true
    $serialPort.RtsEnable = $true
    return $serialPort
}

function Read-SerialLine {
    param([Parameter(Mandatory)][IO.Ports.SerialPort]$SerialPort)

    try {
        return ([string]$SerialPort.ReadLine()).Trim()
    }
    catch {
        # Windows PowerShell can wrap a SerialPort timeout in MethodInvocationException.
        if ($_.Exception -is [TimeoutException] -or
            $_.Exception.InnerException -is [TimeoutException]) {
            return $null
        }
        throw
    }
}

function Open-ValidatedBox1Port {
    $candidates = @(Get-CandidatePortNames)
    if ($candidates.Count -eq 0) {
        throw 'No Raspberry Pi Pico CDC serial device was found.'
    }

    $failures = [Collections.Generic.List[string]]::new()

    foreach ($candidate in $candidates) {
        $serialPort = $null
        try {
            $serialPort = New-Box1SerialPort -Name $candidate
            $serialPort.Open()

            $detectedFirmware = $null
            $sawReady = $false
            $deadline = (Get-Date).AddSeconds($ValidationTimeoutSeconds)

            while ((Get-Date) -lt $deadline) {
                $line = Read-SerialLine -SerialPort $serialPort
                if ($null -eq $line) { continue }

                if ($line -cmatch $FirmwareBannerPattern) {
                    $detectedFirmware = $Matches.Version
                }
                elseif ($line -eq $ExpectedReadyLine) {
                    $sawReady = $true
                }

                if ($null -ne $detectedFirmware -and $sawReady) {
                    return [pscustomobject]@{
                        Port = $serialPort
                        PortName = $candidate
                        Firmware = $detectedFirmware
                    }
                }
            }

            throw "A valid 'BOX1 <version>' banner and '$ExpectedReadyLine' were not both received within $ValidationTimeoutSeconds seconds."
        }
        catch {
            $failures.Add("$candidate`: $($_.Exception.Message)")
            if ($null -ne $serialPort) {
                try { if ($serialPort.IsOpen) { $serialPort.Close() } } catch {}
                $serialPort.Dispose()
            }
        }
    }

    throw ('No candidate produced valid Box 1 startup output. ' + ($failures -join ' | '))
}

function Convert-DbfsToLevel {
    param([Parameter(Mandatory)][double]$Dbfs)

    $level = [Math]::Pow(10.0, ($Dbfs / 20.0))
    return [Math]::Min(1.0, [Math]::Max(0.0, $level))
}

function Get-UpdatedRmsPower {
    param(
        [Parameter(Mandatory)][double]$CurrentPower,
        [Parameter(Mandatory)][double]$TargetLevel,
        [Parameter(Mandatory)][double]$ElapsedMilliseconds
    )

    $targetPower = $TargetLevel * $TargetLevel
    $responseMilliseconds = if ($targetPower -lt $CurrentPower) {
        $RmsDecayMilliseconds
    }
    else {
        $RmsAttackMilliseconds
    }

    if ($responseMilliseconds -le 0) { return $targetPower }

    $coefficient = [Math]::Exp(
        [Math]::Log10(0.01) * $ElapsedMilliseconds / $responseMilliseconds
    )
    return $targetPower + ($coefficient * ($CurrentPower - $targetPower))
}

function Convert-TelemetryLine {
    param([AllowNull()][string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line) -or $Line -notmatch $TelemetryPattern) {
        return $null
    }

    try {
        return [pscustomobject]@{
            LeftRmsDb = [double]::Parse($Matches[1], [Globalization.NumberStyles]::Float, $InvariantCulture)
            LeftPeakDb = [double]::Parse($Matches[2], [Globalization.NumberStyles]::Float, $InvariantCulture)
            LeftVuDb = [double]::Parse($Matches[3], [Globalization.NumberStyles]::Float, $InvariantCulture)
            RightRmsDb = [double]::Parse($Matches[4], [Globalization.NumberStyles]::Float, $InvariantCulture)
            RightPeakDb = [double]::Parse($Matches[5], [Globalization.NumberStyles]::Float, $InvariantCulture)
            RightVuDb = [double]::Parse($Matches[6], [Globalization.NumberStyles]::Float, $InvariantCulture)
        }
    }
    catch {
        return $null
    }
}

$PublisherScript = {
    param(
        [Parameter(Mandatory)][hashtable]$SharedState,
        [Parameter(Mandatory)][Threading.AutoResetEvent]$PublishSignal,
        [Parameter(Mandatory)][string]$PublisherStateFile,
        [Parameter(Mandatory)][string]$PublisherStateTempFile,
        [Parameter(Mandatory)][string]$PublisherHeartbeatFile,
        [Parameter(Mandatory)][string]$PublisherHeartbeatTempFile,
        [Parameter(Mandatory)][string]$PublisherErrorFile,
        [Parameter(Mandatory)][string]$PublisherErrorTempFile,
        [Parameter(Mandatory)][int]$PublisherHeartbeatIntervalSeconds,
        [Parameter(Mandatory)][string]$PublisherRegistrySubKey
    )

    $ErrorActionPreference = 'Stop'
    $publisherCulture = [Globalization.CultureInfo]::InvariantCulture
    $lastPublishedSequence = -1L
    $lastRegistrySequence = -1L
    $nextStatePublication = [DateTime]::MinValue
    $statePublicationFailed = $false
    $registryPublicationFailed = $false
    $nextHeartbeat = [DateTime]::UtcNow
    $registryHandle = [IntPtr]::Zero

    if (-not ('Box1Collector.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Box1Collector
{
    public static class NativeMethods
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

        public static readonly IntPtr HKEY_CURRENT_USER =
            new IntPtr(unchecked((int)0x80000001));

        public static readonly IntPtr HKEY_LOCAL_MACHINE =
            new IntPtr(unchecked((int)0x80000002));

        [DllImport(
            "advapi32.dll",
            EntryPoint = "RegCreateKeyExW",
            CharSet = CharSet.Unicode,
            ExactSpelling = true
        )]
        public static extern int RegCreateKeyExW(
            IntPtr hKey,
            string subKey,
            uint reserved,
            string keyClass,
            uint options,
            int desiredAccess,
            IntPtr securityAttributes,
            out IntPtr resultKey,
            out uint disposition
        );

        [DllImport(
            "advapi32.dll",
            EntryPoint = "RegSetValueExW",
            CharSet = CharSet.Unicode,
            ExactSpelling = true
        )]
        public static extern int RegSetValueExW(
            IntPtr hKey,
            string valueName,
            uint reserved,
            uint valueType,
            byte[] data,
            uint dataSize
        );

        [DllImport("advapi32.dll", ExactSpelling = true)]
        public static extern int RegCloseKey(IntPtr hKey);
    }
}
'@
    }

    function Open-PublisherRegistryKey {
        $handle = [IntPtr]::Zero
        $disposition = [uint32]0
        $result = [Box1Collector.NativeMethods]::RegCreateKeyExW(
            [Box1Collector.NativeMethods]::HKEY_LOCAL_MACHINE,
            $PublisherRegistrySubKey,
            [uint32]0,
            $null,
            [uint32]0,
            2,
            [IntPtr]::Zero,
            [ref]$handle,
            [ref]$disposition
        )

        if ($result -ne 0) {
            throw [System.ComponentModel.Win32Exception]::new(
                $result,
                "RegCreateKeyExW failed for HKLM\$PublisherRegistrySubKey"
            )
        }

        return $handle
    }

    function Set-PublisherRegistryString {
        param(
            [Parameter(Mandatory)][IntPtr]$Key,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Value
        )

        $bytes = [Text.Encoding]::Unicode.GetBytes($Value + [char]0)
        $result = [Box1Collector.NativeMethods]::RegSetValueExW(
            $Key,
            $Name,
            [uint32]0,
            [uint32]1,
            $bytes,
            [uint32]$bytes.Length
        )

        if ($result -ne 0) {
            throw [System.ComponentModel.Win32Exception]::new(
                $result,
                "RegSetValueExW failed for HKLM\$PublisherRegistrySubKey\$Name"
            )
        }
    }

    function Write-PublisherAtomicText {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$TempPath,
            [Parameter(Mandatory)][string]$Content
        )

        [System.IO.File]::WriteAllText(
            $TempPath,
            $Content,
            [System.Text.UTF8Encoding]::new($false)
        )

        if ([System.IO.File]::Exists($Path)) {
            $replaceSucceeded = [Box1Collector.NativeMethods]::ReplaceFileW(
                $Path,
                $TempPath,
                [IntPtr]::Zero,
                [uint32]0,
                [IntPtr]::Zero,
                [IntPtr]::Zero
            )

            if (-not $replaceSucceeded) {
                $nativeErrorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                $nativeError = [System.ComponentModel.Win32Exception]::new($nativeErrorCode)

                throw [System.ComponentModel.Win32Exception]::new(
                    $nativeErrorCode,
                    (
                        "ReplaceFileW failed replacing '{0}' with '{1}' " +
                        "(Win32 error {2}: {3})"
                    ) -f $Path, $TempPath, $nativeErrorCode, $nativeError.Message
                )
            }
        }
        else {
            [System.IO.File]::Move($TempPath, $Path)
        }
    }

    function Write-PublisherError {
        param([Parameter(Mandatory)][string]$Message)

        try {
            $content = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
            Write-PublisherAtomicText `
                -Path $PublisherErrorFile `
                -TempPath $PublisherErrorTempFile `
                -Content $content
        }
        catch {}
    }

    try {
    $registryHandle = Open-PublisherRegistryKey

    while (-not [bool]$SharedState.Stop) {
        $now = [DateTime]::UtcNow
        if ($now -ge $nextHeartbeat) {
            try {
                # Supervision reads mtime, not this text as correctness evidence.
                # Keep the path present: ReplaceFileW can expose a brief missing
                # entry to metadata readers and provoke a false collector restart.
                $bytes = [Text.Encoding]::UTF8.GetBytes((Get-Date -Format 'o'))
                $heartbeat = [IO.File]::Open($PublisherHeartbeatFile,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
                try {$heartbeat.Write($bytes,0,$bytes.Length);$heartbeat.SetLength($bytes.Length)}
                finally {$heartbeat.Dispose()}
            }
            catch {
                Write-PublisherError -Message "Box 1 heartbeat publication failed. $($_.Exception.Message)"
            }
            $nextHeartbeat = $now.AddSeconds($PublisherHeartbeatIntervalSeconds)
        }

        $sample = $SharedState.LatestSample
        if ($null -ne $sample -and
            ([long]$sample.Sequence -gt $lastPublishedSequence -or
             [long]$sample.Sequence -gt $lastRegistrySequence)) {
            $hadPublicationFailure = $statePublicationFailed -or $registryPublicationFailed

            if ([long]$sample.Sequence -gt $lastRegistrySequence) {
                try {
                    Set-PublisherRegistryString -Key $registryHandle -Name 'Connected' -Value '1'
                    Set-PublisherRegistryString -Key $registryHandle -Name 'Ready' -Value '1'
                    Set-PublisherRegistryString -Key $registryHandle -Name 'LeftRmsDb' -Value $sample.LeftRmsDb.ToString('0.0############', $publisherCulture)
                    Set-PublisherRegistryString -Key $registryHandle -Name 'RightRmsDb' -Value $sample.RightRmsDb.ToString('0.0############', $publisherCulture)
                    Set-PublisherRegistryString -Key $registryHandle -Name 'LeftLevel' -Value $sample.LeftLevel.ToString('0.000000', $publisherCulture)
                    Set-PublisherRegistryString -Key $registryHandle -Name 'RightLevel' -Value $sample.RightLevel.ToString('0.000000', $publisherCulture)
                    Set-PublisherRegistryString -Key $registryHandle -Name 'LeftRmsEnvelope' -Value $sample.LeftRmsEnvelope.ToString('0.000000000000', $publisherCulture)
                    Set-PublisherRegistryString -Key $registryHandle -Name 'RightRmsEnvelope' -Value $sample.RightRmsEnvelope.ToString('0.000000000000', $publisherCulture)
                    Set-PublisherRegistryString -Key $registryHandle -Name 'Updated' -Value $sample.ReceiptTimestamp.ToString('yyyy-MM-dd HH:mm:ss.fff', $publisherCulture)
                    # Sequence is the commit marker and is intentionally written last.
                    Set-PublisherRegistryString -Key $registryHandle -Name 'Sequence' -Value ([string]$sample.Sequence)
                    $lastRegistrySequence = [long]$sample.Sequence
                    $registryPublicationFailed = $false
                }
                catch {
                    $registryPublicationFailed = $true
                    Write-PublisherError -Message "Box 1 registry publication failed. $($_.Exception.Message)"
                }
            }

            if ([long]$sample.Sequence -gt $lastPublishedSequence -and $now -ge $nextStatePublication) {
                # Rainmeter uses HKLM synchronously. This compatibility/diagnostic
                # file has no frame-rate reader and must not monopolize delivery.
                $nextStatePublication = $now.AddMilliseconds(200)
                try {
                $lines = @(
                    'Device=BOX1'
                    "Firmware=$($sample.Firmware)"
                    "Port=$($sample.Port)"
                    'Connected=1'
                    'Ready=1'
                    "LeftRmsDb=$($sample.LeftRmsDb.ToString('0.0############', $publisherCulture))"
                    "LeftPeakDb=$($sample.LeftPeakDb.ToString('0.0############', $publisherCulture))"
                    "LeftVuDb=$($sample.LeftVuDb.ToString('0.0############', $publisherCulture))"
                    "RightRmsDb=$($sample.RightRmsDb.ToString('0.0############', $publisherCulture))"
                    "RightPeakDb=$($sample.RightPeakDb.ToString('0.0############', $publisherCulture))"
                    "RightVuDb=$($sample.RightVuDb.ToString('0.0############', $publisherCulture))"
                    "LeftLevel=$($sample.LeftLevel.ToString('0.000000', $publisherCulture))"
                    "RightLevel=$($sample.RightLevel.ToString('0.000000', $publisherCulture))"
                    "Sequence=$($sample.Sequence)"
                    "Updated=$($sample.ReceiptTimestamp.ToString('yyyy-MM-dd HH:mm:ss.fff', $publisherCulture))"
                    ''
                ) -join "`r`n"

                Write-PublisherAtomicText `
                    -Path $PublisherStateFile `
                    -TempPath $PublisherStateTempFile `
                    -Content $lines
                $lastPublishedSequence = [long]$sample.Sequence
                    $statePublicationFailed = $false
                }
                catch {
                    $statePublicationFailed = $true
                    Write-PublisherError -Message "Box 1 state publication failed. $($_.Exception.Message)"
                }
            }

            if ($hadPublicationFailure -and
                -not $statePublicationFailed -and
                -not $registryPublicationFailed) {
                Remove-Item -LiteralPath $PublisherErrorFile -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $PublisherErrorTempFile -Force -ErrorAction SilentlyContinue
            }

            # Recheck immediately. Samples received during publication are coalesced
            # into the newest available sample without delaying serial acquisition.
            # Registry remains signaled at acquisition rate. A pending diagnostic
            # snapshot alone is not a reason to busy-spin between 5 Hz writes.
            if ([long]$SharedState.LatestSample.Sequence -gt $lastRegistrySequence) { continue }
        }

        $millisecondsUntilHeartbeat = [Math]::Ceiling(
            ($nextHeartbeat - [DateTime]::UtcNow).TotalMilliseconds
        )
        $waitMilliseconds = [int][Math]::Max(
            1,
            [Math]::Min([int]::MaxValue, $millisecondsUntilHeartbeat)
        )
        [void]$PublishSignal.WaitOne($waitMilliseconds)
    }
    }
    finally {
        if ($registryHandle -ne [IntPtr]::Zero) {
            [void][Box1Collector.NativeMethods]::RegCloseKey($registryHandle)
        }
    }
}

$DiagnosticWriterScript = {
    param(
        [Parameter(Mandatory)][hashtable]$DiagnosticState,
        [Parameter(Mandatory)]$DiagnosticQueue,
        [Parameter(Mandatory)][Threading.AutoResetEvent]$DiagnosticSignal,
        [Parameter(Mandatory)][Threading.EventWaitHandle]$DiagnosticControlSignal,
        [Parameter(Mandatory)][string]$ControlFile,
        [Parameter(Mandatory)][string]$CaptureRoot
    )

    $ErrorActionPreference = 'Stop'
    $diagnosticCulture = [Globalization.CultureInfo]::InvariantCulture
    $utf8 = [Text.UTF8Encoding]::new($false)
    $captureRootFull = [IO.Path]::GetFullPath($CaptureRoot).TrimEnd('\') + '\'
    $activeCaptureId = $null
    $captureDirectory = $null
    $writer = $null
    $recordsWritten = 0L
    $request = $null

    function Get-CaptureRequest {
        if (-not [IO.File]::Exists($ControlFile)) { return $null }

        try {
            $values = @{}
            foreach ($line in [IO.File]::ReadAllLines($ControlFile)) {
                if ($line -match '^([^=]+)=(.*)$') {
                    $values[$Matches[1]] = $Matches[2]
                }
            }

            if ([string]::IsNullOrWhiteSpace($values.CaptureId) -or
                [string]::IsNullOrWhiteSpace($values.CaptureDirectory)) {
                return $null
            }

            $directory = [IO.Path]::GetFullPath($values.CaptureDirectory)
            if (-not $directory.StartsWith($captureRootFull, [StringComparison]::OrdinalIgnoreCase) -or
                -not [IO.Directory]::Exists($directory)) {
                return $null
            }

            return [pscustomobject]@{
                CaptureId = [string]$values.CaptureId
                CaptureDirectory = $directory
            }
        }
        catch {
            return $null
        }
    }

    function Write-CaptureRecord {
        param([Parameter(Mandatory)][object[]]$Record)

        $timestamp = [DateTime]$Record[1]
        $fields = @(
            $timestamp.ToUniversalTime().Ticks.ToString($diagnosticCulture)
            $timestamp.ToString('o', $diagnosticCulture)
            ([long]$Record[2]).ToString($diagnosticCulture)
            ([double]$Record[3]).ToString('0.0############', $diagnosticCulture)
            ([double]$Record[4]).ToString('0.0############', $diagnosticCulture)
            ([double]$Record[5]).ToString('0.0############', $diagnosticCulture)
            ([double]$Record[6]).ToString('0.0############', $diagnosticCulture)
            ([double]$Record[7]).ToString('0.0############', $diagnosticCulture)
            ([double]$Record[8]).ToString('0.0############', $diagnosticCulture)
        )
        $script:writer.WriteLine($fields -join ',')
        $script:recordsWritten++
    }

    function Drain-CaptureQueue {
        param([AllowNull()][string]$CaptureId)

        $record = $null
        while ($DiagnosticQueue.TryDequeue([ref]$record)) {
            if ($null -ne $CaptureId -and [string]$record[0] -ceq $CaptureId) {
                Write-CaptureRecord -Record $record
            }
            $record = $null
        }
    }

    function Close-Capture {
        param([bool]$CollectorStopping)

        if ($null -eq $script:activeCaptureId) { return }

        $DiagnosticState.CaptureId = $null
        Drain-CaptureQueue -CaptureId $script:activeCaptureId

        if ($null -ne $script:writer) {
            $script:writer.Flush()
            $script:writer.Dispose()
            $script:writer = $null
        }

        $completion = @(
            "CaptureId=$($script:activeCaptureId)"
            "RecordsWritten=$($script:recordsWritten)"
            "CollectorStopping=$([int]$CollectorStopping)"
            "CompletedUtc=$([DateTime]::UtcNow.ToString('o', $diagnosticCulture))"
            ''
        ) -join "`r`n"
        [IO.File]::WriteAllText(
            (Join-Path $script:captureDirectory 'box1_collector_capture.complete'),
            $completion,
            $utf8
        )

        $script:activeCaptureId = $null
        $script:captureDirectory = $null
        $script:recordsWritten = 0L
    }

    $request = Get-CaptureRequest

    try {
        while (-not [bool]$DiagnosticState.Stop) {
            if ($null -ne $activeCaptureId -and
                ($null -eq $request -or $request.CaptureId -cne $activeCaptureId)) {
                Close-Capture -CollectorStopping $false
            }

            if ($null -eq $activeCaptureId -and $null -ne $request) {
                $activeCaptureId = $request.CaptureId
                $captureDirectory = $request.CaptureDirectory
                $recordsWritten = 0L
                $stream = [IO.FileStream]::new(
                    (Join-Path $captureDirectory 'box1_raw.csv'),
                    [IO.FileMode]::Create,
                    [IO.FileAccess]::Write,
                    [IO.FileShare]::Read
                )
                $writer = [IO.StreamWriter]::new($stream, $utf8)
                $writer.WriteLine('UtcTicks,TimestampLocal,Sequence,LeftRmsDb,LeftPeakDb,LeftVuDb,RightRmsDb,RightPeakDb,RightVuDb')
                $writer.Flush()
                [IO.File]::WriteAllText(
                    (Join-Path $captureDirectory 'box1_collector_capture.started'),
                    "CaptureId=$activeCaptureId`r`n",
                    $utf8
                )
                $DiagnosticState.CaptureId = $activeCaptureId
                $DiagnosticState.Error = $null
            }

            if ($null -ne $activeCaptureId) {
                Drain-CaptureQueue -CaptureId $activeCaptureId
            }
            else {
                Drain-CaptureQueue -CaptureId $null
            }

            if (-not $DiagnosticQueue.IsEmpty) {
                if ($DiagnosticControlSignal.WaitOne(0)) {
                    $request = Get-CaptureRequest
                }
            }
            else {
                $waitResult = [Threading.WaitHandle]::WaitAny(
                    [Threading.WaitHandle[]]@($DiagnosticSignal, $DiagnosticControlSignal)
                )
                if ($waitResult -eq 1) {
                    $request = Get-CaptureRequest
                }
            }
        }
    }
    catch {
        $DiagnosticState.CaptureId = $null
        $DiagnosticState.Error = $_.Exception.Message
        if ($null -ne $captureDirectory) {
            try {
                [IO.File]::WriteAllText(
                    (Join-Path $captureDirectory 'box1_collector_capture.error.txt'),
                    $_.Exception.ToString(),
                    $utf8
                )
            }
            catch {}
        }
    }
    finally {
        try { Close-Capture -CollectorStopping $true } catch {}
        if ($null -ne $writer) { try { $writer.Dispose() } catch {} }
    }
}

$sequence = Get-InitialSequence
$connection = $null
$responseStopwatch = [Diagnostics.Stopwatch]::StartNew()
$lastResponseTicks = $responseStopwatch.ElapsedTicks
$leftRmsPower = 0.0
$rightRmsPower = 0.0
$publisherState = [hashtable]::Synchronized(@{
    Stop = $false
    LatestSample = $null
})
$publisherSignal = [Threading.AutoResetEvent]::new($false)
$publisherRunspace = $null
$publisherPowerShell = $null
$publisherAsyncResult = $null
$diagnosticState = [hashtable]::Synchronized(@{
    Stop = $false
    CaptureId = $null
    Error = $null
})
$diagnosticQueue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
$diagnosticSignal = [Threading.AutoResetEvent]::new($false)
$diagnosticControlSignal = [Threading.EventWaitHandle]::new(
    $false,
    [Threading.EventResetMode]::AutoReset,
    $DiagnosticControlEventName
)
$diagnosticRunspace = $null
$diagnosticPowerShell = $null
$diagnosticAsyncResult = $null

try {
    $publisherRunspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $publisherRunspace.Open()

    $publisherPowerShell = [PowerShell]::Create()
    $publisherPowerShell.Runspace = $publisherRunspace
    [void]$publisherPowerShell.AddScript($PublisherScript.ToString())
    [void]$publisherPowerShell.AddArgument($publisherState)
    [void]$publisherPowerShell.AddArgument($publisherSignal)
    [void]$publisherPowerShell.AddArgument($StateFile)
    [void]$publisherPowerShell.AddArgument($StateTempFile)
    [void]$publisherPowerShell.AddArgument($HeartbeatFile)
    [void]$publisherPowerShell.AddArgument($HeartbeatTempFile)
    [void]$publisherPowerShell.AddArgument($ErrorFile)
    [void]$publisherPowerShell.AddArgument($ErrorTempFile)
    [void]$publisherPowerShell.AddArgument($HeartbeatIntervalSeconds)
    [void]$publisherPowerShell.AddArgument($RuntimeRegistrySubKey)
    $publisherAsyncResult = $publisherPowerShell.BeginInvoke()

    $diagnosticRunspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $diagnosticRunspace.Open()

    $diagnosticPowerShell = [PowerShell]::Create()
    $diagnosticPowerShell.Runspace = $diagnosticRunspace
    [void]$diagnosticPowerShell.AddScript($DiagnosticWriterScript.ToString())
    [void]$diagnosticPowerShell.AddArgument($diagnosticState)
    [void]$diagnosticPowerShell.AddArgument($diagnosticQueue)
    [void]$diagnosticPowerShell.AddArgument($diagnosticSignal)
    [void]$diagnosticPowerShell.AddArgument($diagnosticControlSignal)
    [void]$diagnosticPowerShell.AddArgument($DiagnosticControlFile)
    [void]$diagnosticPowerShell.AddArgument($DiagnosticCaptureRoot)
    $diagnosticAsyncResult = $diagnosticPowerShell.BeginInvoke()

    while ($true) {
        try {
            if ($null -eq $connection -or -not $connection.Port.IsOpen) {
                $connection = Open-ValidatedBox1Port
                $leftRmsPower = 0.0
                $rightRmsPower = 0.0
                $lastResponseTicks = $responseStopwatch.ElapsedTicks
                Clear-CollectorError
                Write-Host "$(Get-Date -Format HH:mm:ss) Connected to Box 1 on $($connection.PortName)."
            }

            $line = Read-SerialLine -SerialPort $connection.Port
            if ($null -eq $line) { continue }

            # Startup banners may reappear if the device resets while the port remains open.
            if ($line -cmatch $FirmwareBannerPattern -or $line -eq $ExpectedReadyLine) { continue }

            $telemetry = Convert-TelemetryLine -Line $line
            if ($null -eq $telemetry) { continue }

            if ($sequence -eq [long]::MaxValue) {
                throw 'Box 1 sequence reached Int64 maximum.'
            }
            $sequence++

            $receiptTimestamp = [DateTime]::Now
            $responseTicks = $responseStopwatch.ElapsedTicks
            $elapsedMilliseconds = [Math]::Max(
                0.0,
                (($responseTicks - $lastResponseTicks) * 1000.0 / [Diagnostics.Stopwatch]::Frequency)
            )
            $lastResponseTicks = $responseTicks

            $leftRmsLevel = Convert-DbfsToLevel -Dbfs $telemetry.LeftRmsDb
            $rightRmsLevel = Convert-DbfsToLevel -Dbfs $telemetry.RightRmsDb
            $leftRmsPower = Get-UpdatedRmsPower `
                -CurrentPower $leftRmsPower `
                -TargetLevel $leftRmsLevel `
                -ElapsedMilliseconds $elapsedMilliseconds
            $rightRmsPower = Get-UpdatedRmsPower `
                -CurrentPower $rightRmsPower `
                -TargetLevel $rightRmsLevel `
                -ElapsedMilliseconds $elapsedMilliseconds

            $publisherState.LatestSample = [pscustomobject]@{
                Firmware = $connection.Firmware
                Port = $connection.PortName
                LeftRmsDb = $telemetry.LeftRmsDb
                LeftPeakDb = $telemetry.LeftPeakDb
                LeftVuDb = $telemetry.LeftVuDb
                RightRmsDb = $telemetry.RightRmsDb
                RightPeakDb = $telemetry.RightPeakDb
                RightVuDb = $telemetry.RightVuDb
                LeftLevel = Convert-DbfsToLevel -Dbfs $telemetry.LeftVuDb
                RightLevel = Convert-DbfsToLevel -Dbfs $telemetry.RightVuDb
                LeftRmsEnvelope = [Math]::Min(1.0, [Math]::Sqrt([Math]::Max(0.0, $leftRmsPower)))
                RightRmsEnvelope = [Math]::Min(1.0, [Math]::Sqrt([Math]::Max(0.0, $rightRmsPower)))
                Sequence = $sequence
                ReceiptTimestamp = $receiptTimestamp
            }
            [void]$publisherSignal.Set()

            $captureId = $diagnosticState.CaptureId
            if (-not [string]::IsNullOrWhiteSpace($captureId)) {
                # Diagnostic acquisition is producer-only: no formatting, file I/O,
                # waiting, pacing, or bounded-queue backpressure occurs here.
                $diagnosticQueue.Enqueue([object[]]@(
                    $captureId
                    $receiptTimestamp
                    $sequence
                    $telemetry.LeftRmsDb
                    $telemetry.LeftPeakDb
                    $telemetry.LeftVuDb
                    $telemetry.RightRmsDb
                    $telemetry.RightPeakDb
                    $telemetry.RightVuDb
                ))
                [void]$diagnosticSignal.Set()
            }
        }
        catch {
            $message = $_.Exception.Message
            try { Write-CollectorError -Message $message } catch {}

            if ($null -ne $connection) {
                try { if ($connection.Port.IsOpen) { $connection.Port.Close() } } catch {}
                try { $connection.Port.Dispose() } catch {}
                $connection = $null
            }

            Write-Warning "Box 1 collector reconnecting: $message"
            Start-Sleep -Seconds $ReconnectDelaySeconds
        }
    }
}
finally {
    if ($null -ne $connection) {
        try { if ($connection.Port.IsOpen) { $connection.Port.Close() } } catch {}
        try { $connection.Port.Dispose() } catch {}
    }

    $publisherState.Stop = $true
    [void]$publisherSignal.Set()

    if ($null -ne $publisherAsyncResult) {
        $publisherStopped = $publisherAsyncResult.AsyncWaitHandle.WaitOne(
            [TimeSpan]::FromSeconds($PublisherShutdownTimeoutSeconds)
        )
        if (-not $publisherStopped -and $null -ne $publisherPowerShell) {
            try { $publisherPowerShell.Stop() } catch {}
        }
        if ($null -ne $publisherPowerShell) {
            try { $publisherPowerShell.EndInvoke($publisherAsyncResult) } catch {}
        }
        try { $publisherAsyncResult.AsyncWaitHandle.Dispose() } catch {}
    }

    if ($null -ne $publisherPowerShell) { $publisherPowerShell.Dispose() }
    if ($null -ne $publisherRunspace) { $publisherRunspace.Dispose() }
    $publisherSignal.Dispose()

    $diagnosticState.Stop = $true
    [void]$diagnosticSignal.Set()

    if ($null -ne $diagnosticAsyncResult) {
        $diagnosticStopped = $diagnosticAsyncResult.AsyncWaitHandle.WaitOne(
            [TimeSpan]::FromSeconds($DiagnosticShutdownTimeoutSeconds)
        )
        if (-not $diagnosticStopped -and $null -ne $diagnosticPowerShell) {
            try { $diagnosticPowerShell.Stop() } catch {}
        }
        if ($null -ne $diagnosticPowerShell) {
            try { $diagnosticPowerShell.EndInvoke($diagnosticAsyncResult) } catch {}
        }
        try { $diagnosticAsyncResult.AsyncWaitHandle.Dispose() } catch {}
    }

    if ($null -ne $diagnosticPowerShell) { $diagnosticPowerShell.Dispose() }
    if ($null -ne $diagnosticRunspace) { $diagnosticRunspace.Dispose() }
    $diagnosticSignal.Dispose()
    $diagnosticControlSignal.Dispose()

    try { $singleInstanceMutex.ReleaseMutex() } catch {}
    $singleInstanceMutex.Dispose()
}
