[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ControlFile = Join-Path $PSScriptRoot 'Box1VUComparison.capture'
$RainmeterExe = 'C:\Program Files\Rainmeter\Rainmeter.exe'
$RainmeterConfig = 'Analog_Floating2'
$RainmeterMeasure = 'DashboardVUComparisonCapture'
$ControlEventName = 'Local\RainmeterDenonBox1VUComparisonControl'
$StopTimeoutSeconds = 12

function Signal-CollectorControlChange {
    $signal = [Threading.EventWaitHandle]::new(
        $false,
        [Threading.EventResetMode]::AutoReset,
        $ControlEventName
    )
    try { [void]$signal.Set() }
    finally { $signal.Dispose() }
}

if (-not (Test-Path -LiteralPath $ControlFile -PathType Leaf)) {
    throw "No active Box 1 VU comparison capture was found at $ControlFile"
}

$control = @{}
foreach ($line in Get-Content -LiteralPath $ControlFile) {
    if ($line -match '^([^=]+)=(.*)$') {
        $control[$Matches[1]] = $Matches[2]
    }
}
if ([string]::IsNullOrWhiteSpace($control.CaptureDirectory)) {
    throw 'The active capture control file does not contain CaptureDirectory.'
}
$captureDirectory = [IO.Path]::GetFullPath($control.CaptureDirectory)
$captureRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'captures')).TrimEnd('\') + '\'
if (-not $captureDirectory.StartsWith($captureRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "CaptureDirectory is outside the diagnostic capture root: $captureDirectory"
}

Remove-Item -LiteralPath $ControlFile -Force
Signal-CollectorControlChange
if (Test-Path -LiteralPath $RainmeterExe -PathType Leaf) {
    & $RainmeterExe '!CommandMeasure' $RainmeterMeasure 'StopCapture()' $RainmeterConfig
}

$collectorComplete = Join-Path $captureDirectory 'box1_collector_capture.complete'
$rainmeterComplete = Join-Path $captureDirectory 'rainmeter_capture.complete'
$collectorError = Join-Path $captureDirectory 'box1_collector_capture.error.txt'
$rainmeterError = Join-Path $captureDirectory 'rainmeter_capture.error.txt'
$deadline = [DateTime]::UtcNow.AddSeconds($StopTimeoutSeconds)
while ([DateTime]::UtcNow -lt $deadline) {
    if ((Test-Path -LiteralPath $collectorComplete -PathType Leaf) -and
        (Test-Path -LiteralPath $rainmeterComplete -PathType Leaf)) {
        break
    }
    Start-Sleep -Milliseconds 100
}

if (Test-Path -LiteralPath $RainmeterExe -PathType Leaf) {
    & $RainmeterExe '!DisableMeasure' $RainmeterMeasure $RainmeterConfig
}

$missing = @()
if (-not (Test-Path -LiteralPath $collectorComplete -PathType Leaf)) {
    $missing += 'Box1Collector completion marker'
}
if (-not (Test-Path -LiteralPath $rainmeterComplete -PathType Leaf)) {
    $missing += 'Rainmeter completion marker'
}
if (Test-Path -LiteralPath $collectorError -PathType Leaf) {
    $missing += "Box1Collector error: $(Get-Content -Raw -LiteralPath $collectorError)"
}
if (Test-Path -LiteralPath $rainmeterError -PathType Leaf) {
    $missing += "Rainmeter error: $(Get-Content -Raw -LiteralPath $rainmeterError)"
}

Write-Host 'Box 1 VU comparison capture stopped.'
Write-Host "Capture folder: $captureDirectory"
Write-Host "Analyze with: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Analyze-Box1VUComparison.ps1`" -CaptureDirectory `"$captureDirectory`""

if ($missing.Count -gt 0) {
    throw ('Capture stopped, but completion was not confirmed for: ' + ($missing -join ', '))
}
