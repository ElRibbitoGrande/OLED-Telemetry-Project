[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$CaptureRoot = Join-Path $PSScriptRoot 'captures'
$ControlFile = Join-Path $PSScriptRoot 'Box1VUComparison.capture'
$RainmeterExe = 'C:\Program Files\Rainmeter\Rainmeter.exe'
$RainmeterConfig = 'Analog_Floating2'
$RainmeterMeasure = 'DashboardVUComparisonCapture'
$ControlEventName = 'Local\RainmeterDenonBox1VUComparisonControl'
$StartTimeoutSeconds = 8
$Utf8 = [Text.UTF8Encoding]::new($false)

function Signal-CollectorControlChange {
    $signal = [Threading.EventWaitHandle]::new(
        $false,
        [Threading.EventResetMode]::AutoReset,
        $ControlEventName
    )
    try { [void]$signal.Set() }
    finally { $signal.Dispose() }
}

if (Test-Path -LiteralPath $ControlFile -PathType Leaf) {
    throw "A Box 1 VU comparison capture is already active: $ControlFile"
}
if (-not (Test-Path -LiteralPath $RainmeterExe -PathType Leaf)) {
    throw "Rainmeter was not found at $RainmeterExe"
}
if (-not (Get-Process -Name Rainmeter -ErrorAction SilentlyContinue)) {
    throw 'Rainmeter is not currently running.'
}

[IO.Directory]::CreateDirectory($CaptureRoot) | Out-Null
$captureId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$captureDirectory = Join-Path $CaptureRoot "Box1VUComparison_$captureId"
[IO.Directory]::CreateDirectory($captureDirectory) | Out-Null

$controlContent = @(
    "CaptureId=$captureId"
    "CaptureDirectory=$captureDirectory"
    "StartedUtcTicks=$([DateTime]::UtcNow.Ticks)"
    ''
) -join "`r`n"
$controlTemp = "$ControlFile.tmp"

try {
    [IO.File]::WriteAllText($controlTemp, $controlContent, $Utf8)
    [IO.File]::Move($controlTemp, $ControlFile)
    Signal-CollectorControlChange

    & $RainmeterExe '!EnableMeasure' $RainmeterMeasure $RainmeterConfig
    & $RainmeterExe '!UpdateMeasure' $RainmeterMeasure $RainmeterConfig

    $collectorStarted = Join-Path $captureDirectory 'box1_collector_capture.started'
    $rainmeterStarted = Join-Path $captureDirectory 'rainmeter_capture.started'
    $collectorError = Join-Path $captureDirectory 'box1_collector_capture.error.txt'
    $rainmeterError = Join-Path $captureDirectory 'rainmeter_capture.error.txt'
    $deadline = [DateTime]::UtcNow.AddSeconds($StartTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ((Test-Path -LiteralPath $collectorError -PathType Leaf) -or
            (Test-Path -LiteralPath $rainmeterError -PathType Leaf)) {
            break
        }
        if ((Test-Path -LiteralPath $collectorStarted -PathType Leaf) -and
            (Test-Path -LiteralPath $rainmeterStarted -PathType Leaf)) {
            break
        }
        Start-Sleep -Milliseconds 100
    }

    if (Test-Path -LiteralPath $collectorError -PathType Leaf) {
        throw "The Box1Collector diagnostic writer failed: $(Get-Content -Raw -LiteralPath $collectorError)"
    }
    if (Test-Path -LiteralPath $rainmeterError -PathType Leaf) {
        throw "The Rainmeter diagnostic measure failed: $(Get-Content -Raw -LiteralPath $rainmeterError)"
    }
    if (-not (Test-Path -LiteralPath $collectorStarted -PathType Leaf)) {
        throw 'The Box1Collector diagnostic writer did not acknowledge the capture.'
    }
    if (-not (Test-Path -LiteralPath $rainmeterStarted -PathType Leaf)) {
        throw 'The Analog_Floating2 Rainmeter diagnostic measure did not acknowledge the capture.'
    }
}
catch {
    Remove-Item -LiteralPath $ControlFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $controlTemp -Force -ErrorAction SilentlyContinue
    try { Signal-CollectorControlChange } catch {}
    try { & $RainmeterExe '!DisableMeasure' $RainmeterMeasure $RainmeterConfig } catch {}
    throw
}

Write-Host 'Box 1 VU comparison capture started.'
Write-Host "Capture folder: $captureDirectory"
Write-Host 'Play the same track through Windows and WiiM for 60-90 seconds.'
Write-Host "Stop with: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Stop-Box1VUComparisonCapture.ps1`""
