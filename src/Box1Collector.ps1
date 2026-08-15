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

function Write-Heartbeat {
    Write-AtomicText `
        -Path $HeartbeatFile `
        -TempPath $HeartbeatTempFile `
        -Content (Get-Date -Format 'o')
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
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) { return 0L }

    try {
        foreach ($line in Get-Content -LiteralPath $StateFile -ErrorAction Stop) {
            if ($line -match '^Sequence=(\d+)$') {
                return [long]::Parse($Matches[1], $InvariantCulture)
            }
        }
    }
    catch {}

    return 0L
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

function Format-DbValue {
    param([Parameter(Mandatory)][double]$Value)
    return $Value.ToString('0.0############', $InvariantCulture)
}

function Format-LevelValue {
    param([Parameter(Mandatory)][double]$Value)
    return $Value.ToString('0.000000', $InvariantCulture)
}

function Publish-Box1State {
    param(
        [Parameter(Mandatory)]$Telemetry,
        [Parameter(Mandatory)][string]$ActualPortName,
        [Parameter(Mandatory)][string]$Firmware,
        [Parameter(Mandatory)][long]$Sequence
    )

    $leftLevel = Convert-DbfsToLevel -Dbfs $Telemetry.LeftVuDb
    $rightLevel = Convert-DbfsToLevel -Dbfs $Telemetry.RightVuDb

    $lines = @(
        'Device=BOX1'
        "Firmware=$Firmware"
        "Port=$ActualPortName"
        'Connected=1'
        'Ready=1'
        "LeftRmsDb=$(Format-DbValue $Telemetry.LeftRmsDb)"
        "LeftPeakDb=$(Format-DbValue $Telemetry.LeftPeakDb)"
        "LeftVuDb=$(Format-DbValue $Telemetry.LeftVuDb)"
        "RightRmsDb=$(Format-DbValue $Telemetry.RightRmsDb)"
        "RightPeakDb=$(Format-DbValue $Telemetry.RightPeakDb)"
        "RightVuDb=$(Format-DbValue $Telemetry.RightVuDb)"
        "LeftLevel=$(Format-LevelValue $leftLevel)"
        "RightLevel=$(Format-LevelValue $rightLevel)"
        "Sequence=$Sequence"
        "Updated=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
        ''
    ) -join "`r`n"

    Write-AtomicText -Path $StateFile -TempPath $StateTempFile -Content $lines
}

$sequence = Get-InitialSequence
$connection = $null
$nextHeartbeat = Get-Date

try {
    while ($true) {
        try {
            if ($null -eq $connection -or -not $connection.Port.IsOpen) {
                $connection = Open-ValidatedBox1Port
                Clear-CollectorError
                Write-Host "$(Get-Date -Format HH:mm:ss) Connected to Box 1 on $($connection.PortName)."
            }

            if ((Get-Date) -ge $nextHeartbeat) {
                Write-Heartbeat
                $nextHeartbeat = (Get-Date).AddSeconds($HeartbeatIntervalSeconds)
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
            Publish-Box1State `
                -Telemetry $telemetry `
                -ActualPortName $connection.PortName `
                -Firmware $connection.Firmware `
                -Sequence $sequence
            Clear-CollectorError
        }
        catch {
            $message = $_.Exception.Message
            try { Write-CollectorError -Message $message } catch {}
            try { Write-Heartbeat } catch {}

            if ($null -ne $connection) {
                try { if ($connection.Port.IsOpen) { $connection.Port.Close() } } catch {}
                try { $connection.Port.Dispose() } catch {}
                $connection = $null
            }

            Write-Warning "Box 1 collector reconnecting: $message"
            Start-Sleep -Seconds $ReconnectDelaySeconds
            $nextHeartbeat = Get-Date
        }
    }
}
finally {
    if ($null -ne $connection) {
        try { if ($connection.Port.IsOpen) { $connection.Port.Close() } } catch {}
        try { $connection.Port.Dispose() } catch {}
    }
    try { $singleInstanceMutex.ReleaseMutex() } catch {}
    $singleInstanceMutex.Dispose()
}
